# Sensu plugin for monitoring network interfaces

A sensu plugin to efficiently monitor network interfaces on Linux allowing to track metrics like speed, duplex, operational status, link carrier etc.

The plugin generates multiple OK/WARN/CRIT/UNKNOWN events via the sensu client socket (https://sensuapp.org/docs/latest/clients#client-socket-input) so that you
do not miss state changes when monitoring multiple interfaces + metrics.

## Usage

The plugin accepts command line options to specify things like expected mtu, speed, duplex, operstate etc.

```
Usage: check-network-interface.rb (options)
        --carrier <STATE>            Indicates the current physical link state of the interface (default: up)
    -c, --config <PATH>              Optional configuration file (default: ./network-interface.json)
    -d, --duplex <STATE>             Check interface duplex settings (default: full)
    -x <INTERFACES>,                 Comma separated list of interfaces to ignore
        --ignore-interface
    -X <INTERFACES>,                 Comma separated list of Interfaces to ignore (regex)
        --ignore-interface-regex
    -i, --interface <INTERFACES>     Comma separated list of interfaces to check (default: ALL)
    -I <INTERFACES>,                 Comma separated list of interfaces to check (regex)
        --interface-regex
    -m, --mtu <MTU>                  Message Transfer Unit
        --operstate <STATE>          Indicates the interface RFC2863 operational state (default: up)
    -s, --speed <SPEED>              Expected speed in Mb/s
    -t, --txqueuelen <TXQUEUELEN>    Transmit Queue Length
    -w, --warn                       Warn instead of throwing a critical failure
```

By default, command line option parameters are global to all interfaces. However, each interface can override the defaults either in their ifcfg configuration files (e.g. MTU) or
in an optional JSON configuration file which must be placed in the same location as the plugin.

JSON example:

```
{
  "interfaces": {
    "eth0": {
      "operstate": "down",
      "carrier": "down"
      "duplex": "full",
      "speed": 10000,
      "mtu": 9000,
      "txqueuelen": 10000
    },
    ...
  }
}
```

Ideally, you would manage the configuration file via your favourite cfgmgmt tool (e.g. Puppet).

## Author
Matteo Cerutti - <matteo.cerutti@hotmail.co.uk>
