# fctrl-observers-mod

`fctrl-observers-mod` is a mod for Factorio that augments the programmable speaker to collect and export metrics and watch for alert conditions. Integration with [fctrl](https://github.com/circlesabound/fctrl) enables a full end-to-end telemetry solution for your factory, and allows you to monitor custom production statistics and be notified of events outside of the game.

***THIS IS A WORK IN PROGRESS***

## Features

- Set up one-shot alerts to fire on a circuit condition
- Transform any circuit value into a custom tagged metric
- Pre-aggregate metrics either as average/tick or sum

## Integration with `fctrl`

This mod is designed to be used with [fctrl](https://github.com/circlesabound/fctrl), a Factorio server management solution. Statistics and alerts are exported from the game by writing to the process stdout, which `fctrl` captures for ingestion. Therefore, it is (basically) pointless to install this mod if you are not using `fctrl`.
