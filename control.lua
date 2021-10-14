local Entity = require('__stdlib__/stdlib/entity/entity')
local Event = require('__stdlib__/stdlib/event/event')
local Position = require('__stdlib__/stdlib/area/position')
local table = require('__stdlib__/stdlib/utils/table')

--
-- Non GUI functions
--

local function init_global_for_player(player)
    global.players[player.index] = {
        gui_refs = {}
    }
end

local function cleanup_global_for_player(player)
    global.players[player.index] = nil
end

local function should_fire_oneshot(entity, oneshot_data)
    local ret = false
    if entity.valid and oneshot_data and not oneshot_data.fired then
        local cb = entity.get_control_behavior()
        if cb then
            if cb.circuit_condition.fulfilled and oneshot_data.enabled then
                ret = true
            end
        end
    end
    return ret
end

local function fire_oneshot(entity, oneshot_data)
    local out_file = "fctrl_observers/oneshot.json"
    local pos = Position.new(entity.position)
    local tab = {
        position = pos,
        message = oneshot_data.text
    }
    local json = game.table_to_json(tab)
    print("FCTRL_RPC oneshot "..json)
    oneshot_data.fired = true
end

local function accumulate(entity, stream_data)
    -- Get cicuit value, otherwise 0
    local v = 0
    if stream_data.signal_id then
        v = entity.get_merged_signal(stream_data.signal_id)
    end

    stream_data.accumulated_value = stream_data.accumulated_value + v
end

local function should_send_stream(entity, stream_data)
    local ret = false
    if entity.valid and stream_data then
        if stream_data.enabled then
            ret = true
        end
    end
    return ret
end

local function aggregate_and_build_stream_msg(entity, stream_data)
    local k = stream_data.key

    -- Aggregate accumulated value according to the specified strategy
    local aggregated_value = 0
    if stream_data.agg_type == "avg" then
        -- avg per tick
        aggregated_value = stream_data.accumulated_value / 300
    elseif stream_data.agg_type == "sum" then
        -- sum over entire period
        aggregated_value = stream_data.accumulated_value
    end

    -- reset accumulated value
    stream_data.accumulated_value = 0

    return {
        key = k,
        value = aggregated_value
    }
end

local function send_stream_msgs(stream_msgs)
    local out_table = {
        timestamp = game.tick,
        data = stream_msgs
    }
    local json = game.table_to_json(out_table)
    print("FCTRL_RPC stream "..json)
end

local function __debug_fire_oneshot(entity_unit_number)
    local entity = global.assoc_entities_by_unit_number[entity_unit_number]
    if entity and entity.valid then
        local observer_data = Entity.get_data(entity)
        fire_oneshot(entity, observer_data.oneshot)
    end
end

local function add_unique_stream_key(key, entity_unit_number)
    if global.stream_keys[key] then
        -- make it unique
        return add_unique_stream_key(key..math.random(9999), entity_unit_number)
    else
        global.stream_keys[key] = entity_unit_number
        return key
    end
end

local function remove_unique_stream_key(key)
    global.stream_keys[key] = nil
end

local function clock_tick(tick)
    local stream_msgs = {}
    for _, entity in pairs(global.assoc_entities_by_unit_number) do
        local observer_data = Entity.get_data(entity)
        -- handle oneshot
        if should_fire_oneshot(entity, observer_data.oneshot) then
            fire_oneshot(entity, observer_data.oneshot)
        end
        -- accumulate stream data
        accumulate(entity, observer_data.stream)
        -- run aggregation over accumulated stream data every 300 ticks == 5 seconds
        if tick % 300 == 0 then
            if should_send_stream(entity, observer_data.stream) then
                local msg = aggregate_and_build_stream_msg(entity, observer_data.stream)
                stream_msgs[msg.key] = msg.value
            end
        end
    end

    if tick % 300 == 0 then
        send_stream_msgs(stream_msgs)
    end
end

--
-- GUI functions
--

local function gui_create(player_index, observer_data)
    local player = game.get_player(player_index)
    local oneshot_data = observer_data.oneshot
    local stream_data = observer_data.stream

    -- store the gui entities in a table for easier traversal
    local gui_refs = {}

    local anchor = {
        gui = defines.relative_gui_type.programmable_speaker_gui,
        position = defines.relative_gui_position.right
    }
    local observers_frame = player.gui.relative.add {
        type = "frame",
        anchor = anchor,
        caption = {"fctrl-observers.gui-frame-caption"},
        direction = "vertical"
    }
    gui_refs.frame = observers_frame

    local content_frame = observers_frame.add {
        type = "frame",
        direction = "vertical",
        style = "inside_shallow_frame_with_padding"
    }

    local content_flow = content_frame.add {
        type = "flow",
        direction = "vertical",
        style = "inset_frame_container_vertical_flow"
    }

    local flow0 = content_flow.add {
        type = "flow",
        direction = "horizontal",
        style = "inset_frame_container_horizontal_flow_in_tabbed_pane"
    }
    gui_refs.stream_enable_checkbox = flow0.add {
        type = "checkbox",
        name = "fctrl_observers_stream_enable_checkbox",
        caption = {"fctrl-observers.gui-stream-enable-label"},
        state = stream_data.enabled,
        enabled = stream_data.key and stream_data.key ~= "",
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }

    local stream_agg_types = content_flow.add {
        type = "flow",
        direction = "horizontal",
        style = "inset_frame_container_horizontal_flow_in_tabbed_pane"
    }
    stream_agg_types.style.vertical_align = "center"
    gui_refs.agg_type_avg = stream_agg_types.add {
        type = "radiobutton",
        name = "fctrl_observers_stream_agg_avg",
        caption = {"fctrl-observers.gui-stream-agg-avg-label"},
        state = stream_data.agg_type == "avg",
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }
    gui_refs.agg_type_sum = stream_agg_types.add {
        type = "radiobutton",
        name = "fctrl_observers_stream_agg_sum",
        caption = {"fctrl-observers.gui-stream-agg-sum-label"},
        state = stream_data.agg_type == "sum",
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }

    local flow2 = content_flow.add {
        type = "flow",
        direction = "horizontal",
        style = "inset_frame_container_horizontal_flow_in_tabbed_pane"
    }
    flow2.style.vertical_align = "center"
    gui_refs.stream_key = flow2.add {
        type = "textfield",
        name = "fctrl_observers_stream_key",
        text = stream_data.key,
        enabled = not stream_data.enabled,
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }
    gui_refs.stream_key.style.width = 145
    flow2.add {
        type = "label",
        caption = ":"
    }
    if stream_data.signal_id and stream_data.signal_id.type then
        gui_refs.stream_signal_id = flow2.add {
            type = "choose-elem-button",
            name = "fctrl_observers_stream_signal_id",
            elem_type = "signal",
            signal = {
                type = stream_data.signal_id.type,
                name = stream_data.signal_id.name
            },
            style = "slot_button_in_shallow_frame",
            tags = {
                entity_unit_number = observer_data.unit_number
            }
        }
    else
        gui_refs.stream_signal_id = flow2.add {
            type = "choose-elem-button",
            name = "fctrl_observers_stream_signal_id",
            elem_type = "signal",
            style = "slot_button_in_shallow_frame",
            tags = {
                entity_unit_number = observer_data.unit_number
            }
        }
    end

    content_flow.add {
        type = "line"
    }

    local flow3 = content_flow.add {
        type = "flow",
        direction = "horizontal",
        style = "inset_frame_container_horizontal_flow_in_tabbed_pane"
    }
    gui_refs.oneshot_enable_checkbox = flow3.add {
        type = "checkbox",
        name = "fctrl_observers_oneshot_enable_checkbox",
        caption = {"fctrl-observers.gui-oneshot-enable-label"},
        state = oneshot_data.enabled,
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }
    
    -- flow3.add {
    --     type = "empty-widget",
    --     style = "fake_slot"
    -- }

    gui_refs.oneshot_reset = flow3.add {
        type = "button",
        name = "fctrl_observers_oneshot_reset",
        style = "rounded_button",
        caption = {"fctrl-observers.gui-oneshot-reset"},
        enabled = (oneshot_data.enabled and oneshot_data.fired),
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }

    local flow4 = content_flow.add {
        type = "flow",
        direction = "horizontal",
        style = "inset_frame_container_horizontal_flow_in_tabbed_pane"
    }
    flow4.style.horizontally_stretchable = true
    local flow5 = flow4.add {
        type = "flow",
        direction = "vertical"
    }
    flow5.style.horizontally_stretchable = true
    flow5.add {
        type = "frame",
        direction = "horizontal",
        caption = {"fctrl-observers.gui-oneshot-text-label"},
        style = "invisible_frame_with_title"
    }
    local oneshot_text = flow5.add {
        type = "text-box",
        name = "fctrl_observers_oneshot_text",
        text = oneshot_data.text,
        tags = {
            entity_unit_number = observer_data.unit_number
        }
    }
    oneshot_text.word_wrap = true
    oneshot_text.style.minimal_height = 56
    oneshot_text.style.horizontally_stretchable = true
    -- oneshot_text.style.minimal_width = flow4.style.width
    gui_refs.oneshot_text = oneshot_text

    return gui_refs
end

local function gui_destroy(player_index, entity)
    local gui_refs_all = global.players[player_index].gui_refs
    if gui_refs_all then
        local gui_refs = gui_refs_all[entity.unit_number]
        if gui_refs then
            gui_refs.frame.destroy()
        end
    end
end

local function gui_update_oneshot_text(player_index, entity, text)
    local observer_data = Entity.get_data(entity)
    observer_data.oneshot.text = text
end

local function gui_reset_oneshot(player_index, entity)
    local observer_data = Entity.get_data(entity)
    observer_data.oneshot.fired = false
    -- reflect in gui
    local gui_refs = global.players[player_index].gui_refs[entity.unit_number]
    gui_refs.oneshot_reset.enabled = false
end

local function gui_toggle_oneshot_mode(player_index, entity)
    local observer_data = Entity.get_data(entity)
    local oneshot_data = observer_data.oneshot
    -- toggle mode
    oneshot_data.enabled = not oneshot_data.enabled
    oneshot_data.fired = false
    -- reflect in gui
    local gui_refs = global.players[player_index].gui_refs[entity.unit_number]
    gui_refs.oneshot_text.enabled = oneshot_data.enabled
    gui_refs.oneshot_reset.enabled = false
end

local function gui_update_stream_key(player_index, entity, text)
    local observer_data = Entity.get_data(entity)
    observer_data.stream.key = text
    -- cannot enable streaming if key is empty
    local gui_refs = global.players[player_index].gui_refs[entity.unit_number]
    if text and text ~= "" then
        gui_refs.stream_enable_checkbox.enabled = true
    else
        gui_refs.stream_enable_checkbox.enabled = false
    end
end

local function gui_update_stream_signal_id(player_index, entity, signal_id)
    local observer_data = Entity.get_data(entity)
    observer_data.stream.signal_id = table.deepcopy(signal_id)
end

local function gui_toggle_stream_mode(player_index, entity)
    local observer_data = Entity.get_data(entity)
    local stream_data = observer_data.stream
    local gui_refs = global.players[player_index].gui_refs[entity.unit_number]

    local target_stream_mode = not stream_data.enabled
    if target_stream_mode == true then
        -- register unique stream key (and the entity unit number so we can clean up on destroy)
        local resultant_key = add_unique_stream_key(stream_data.key, entity.unit_number)
        if resultant_key ~= stream_data.key then
            -- we changed the stream key in the process
            global.players[player_index].print("De-duped stream key")
            gui_refs.stream_key.text = resultant_key
            gui_update_stream_key(player_index, entity, resultant_key)
        end
    else
        remove_unique_stream_key(stream_data.key)
    end

    -- toggle mode
    stream_data.enabled = not stream_data.enabled
    -- reflect in gui
    gui_refs.stream_key.enabled = not stream_data.enabled
end

local function gui_set_stream_agg_type(player_index, entity, agg_type)
    local observer_data = Entity.get_data(entity)
    local stream_data = observer_data.stream
    local gui_refs = global.players[player_index].gui_refs[entity.unit_number]

    if agg_type == "avg" then
        stream_data.agg_type = "avg"
        gui_refs.agg_type_avg.state = true
        gui_refs.agg_type_sum.state = false
    elseif agg_type == "sum" then
        stream_data.agg_type = "sum"
        gui_refs.agg_type_avg.state = false
        gui_refs.agg_type_sum.state = true
    end
end

--
-- Event handlers
--

Event.on_init(function()
    global.players = {}
    global.assoc_entities_by_unit_number = {}
    global.stream_keys = {}

    for _, player in pairs(game.players) do
        init_global_for_player(player)
    end
end)

Event.on_event(defines.events.on_player_created, function(event)
    local player = game.get_player(event.player_index)
    init_global_for_player(player)
end)

Event.on_event(defines.events.on_player_removed, function(event)
    local player = game.get_player(event.player_index)
    cleanup_global_for_player(player)
end)

Event.on_event(defines.events.on_tick, function(event)
    if global and global.players and global.assoc_entities_by_unit_number and global.stream_keys then
        clock_tick(game.tick)
    end
end)

Event.on_event(defines.events.on_gui_opened, function(event)
    if event.gui_type == defines.gui_type.entity and event.entity.type == "programmable-speaker" then
        gui_destroy(event.player_index, event.entity)
        local observer_data = Entity.get_data(event.entity)
        if not observer_data then
            -- New observer:
            --    populate default data
            --    register unit number mapping to global table
            --    register on_entity_destroyed event
            oneshot_data = {
                enabled = false,
                text = "",
                fired = false
            }
            stream_data = {
                enabled = false,
                agg_type = "avg",
                key = "",
                signal_id = nil,
                accumulated_value = 0
            }
            observer_data = {
                unit_number = event.entity.unit_number,
                oneshot = oneshot_data,
                stream = stream_data
            }
            global.assoc_entities_by_unit_number[event.entity.unit_number] = event.entity
            script.register_on_entity_destroyed(event.entity)
            Entity.set_data(event.entity, observer_data)
        end
        local gui_refs = gui_create(event.player_index, observer_data)
        global.players[event.player_index].gui_refs[event.entity.unit_number] = gui_refs
    end
end)

Event.on_event(defines.events.on_gui_closed, function(event)
    if event.gui_type == defines.gui_type.entity and event.entity.type == "programmable-speaker" then
        gui_destroy(event.player_index, event.entity)
        global.players[event.player_index].gui_refs[event.entity.unit_number] = nil
    end
end)

Event.on_event(defines.events.on_gui_checked_state_changed, function(event)
    local entity_unit_number = event.element.tags.entity_unit_number
    local entity = global.assoc_entities_by_unit_number[entity_unit_number]
    if event.element.name == "fctrl_observers_oneshot_enable_checkbox" then
        gui_toggle_oneshot_mode(event.player_index, entity)
    elseif event.element.name == "fctrl_observers_stream_enable_checkbox" then
        gui_toggle_stream_mode(event.player_index, entity)
    elseif event.element.name == "fctrl_observers_stream_agg_avg" then
        gui_set_stream_agg_type(event.player_index, entity, "avg")
    elseif event.element.name == "fctrl_observers_stream_agg_sum" then
        gui_set_stream_agg_type(event.player_index, entity, "sum")
    end
end)

Event.on_event(defines.events.on_gui_text_changed, function(event)
    if event.element.name == "fctrl_observers_oneshot_text" then
        local entity_unit_number = event.element.tags.entity_unit_number
        local entity = global.assoc_entities_by_unit_number[entity_unit_number]
        gui_update_oneshot_text(event.player_index, entity, event.element.text)
    elseif event.element.name == "fctrl_observers_stream_key" then
        local entity_unit_number = event.element.tags.entity_unit_number
        local entity = global.assoc_entities_by_unit_number[entity_unit_number]
        gui_update_stream_key(event.player_index, entity, event.element.text)
    end
end)

Event.on_event(defines.events.on_gui_elem_changed, function(event)
    if event.element.name == "fctrl_observers_stream_signal_id" then
        local entity_unit_number = event.element.tags.entity_unit_number
        local entity = global.assoc_entities_by_unit_number[entity_unit_number]
        gui_update_stream_signal_id(event.player_index, entity, event.element.elem_value)
    end
end)

Event.on_event(defines.events.on_gui_click, function(event)
    if event.element.name == "fctrl_observers_oneshot_reset" then
        local entity_unit_number = event.element.tags.entity_unit_number
        local entity = global.assoc_entities_by_unit_number[entity_unit_number]
        gui_reset_oneshot(event.player_index, entity)
    end
end)

Event.on_event(defines.events.on_entity_destroyed, function(event)
    global.assoc_entities_by_unit_number[event.unit_number] = nil

    -- linear search through stream key table to remove entry
    for stream_key, unit_number in pairs(global.stream_keys) do
        if unit_number == event.unit_number then
            global.stream_keys[stream_key] = nil
            break
        end
    end
end)
