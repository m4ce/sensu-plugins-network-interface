#!/usr/bin/env ruby
#
# check-network-interface.rb
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

require 'sensu-plugin/check/cli'
require 'socket'

class CheckNetworkInterface < Sensu::Plugin::Check::CLI
  option :interface,
         :description => "Comma separated list of interfaces to check (default: ALL)",
         :short => "-i <INTERFACES>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :rinterface,
         :description => "Comma separated list of interfaces to check (regex)",
         :short => "-I <INTERFACES>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :ignore_interface,
         :description => "Comma separated list of interfaces to ignore",
         :short => "-x <INTERFACES>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :rignore_interface,
         :description => "Comma separated list of Interfaces to ignore (regex)",
         :short => "-X <INTERFACES>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :config_file,
         :description => "Optional configuration file (default: #{File.dirname(__FILE__)}/network-interface.json)",
         :short => "-c <PATH>",
         :long => "--config <PATH>",
         :default => File.dirname(__FILE__) + "/network-interface.json"

  option :speed,
         :description => "Expected speed in Mb/s",
         :short => "-s <SPEED>",
         :long => "--speed <SPEED>",
         :proc => proc(&:to_i),
         :default => nil

  option :mtu,
         :description => 'Message Transfer Unit',
         :short => "-m <MTU>",
         :long => "--mtu <MTU>",
         :proc => proc(&:to_i),
         :default => nil

  option :txqueuelen,
         :description => 'Transmit Queue Length',
         :short => "-t <TXQUEUELEN>",
         :long => "--txqueuelen <TXQUEUELEN>",
         :proc => proc(&:to_i),
         :default => nil

  option :duplex,
         :description => "Check interface duplex settings (default: full)",
         :short => "-d <STATE>",
         :long => "--duplex <STATE>",
         :in => ["half", "full"],
         :default => "full"

  option :operstate,
         :description => "Indicates the interface RFC2863 operational state (default: up)",
         :long => "--operstate <STATE>",
         :in => ["unknown", "notpresent", "down", "lowerlayerdown", "testing", "dormant", "up"],
         :default => "up"

  option :carrier,
         :description => "Indicates the current physical link state of the interface (default: up)",
         :long => "--carrier <STATE>",
         :in => ["down", "up"],
         :default => "up"

  option :warn,
         :description => "Warn instead of throwing a critical failure",
         :short => "-w",
         :long => "--warn",
         :boolean => false

  def initialize()
    super

    @interfaces = []
    find_interfaces().each do |interface|
      if config[:ignore_interface].size > 0
        next if config[:ignore_interface].include?(interface)
      end

      if config[:rignore_interface].size > 0
        b = false
        config[:rignore_interface].each do |ignore_interface|
          if interface =~ Regexp.new(ignore_interface)
            b = true
            break
          end
        end
        next if b
      end

      if config[:interface].size > 0
        next unless config[:interface].include?(interface)
      end

      if config[:rinterface].size > 0
        b = true
        config[:rinterface].each do |rinterface|
          if interface =~ Regexp.new(rinterface)
            b = false
            break
          end
        end
        next if b
      end

      @interfaces << interface
    end

    @json_config = nil
    if File.exists?(config[:config_file])
      require 'json'
      @json_config = JSON.parse(File.read(config[:config_file]))
    end
  end

  def send_client_socket(data)
    sock = UDPSocket.new
    sock.send(data + "\n", 0, "127.0.0.1", 3030)
  end

  def send_ok(check_name, msg)
    event = {"name" => check_name, "status" => 0, "output" => "OK: #{msg}", "handler" => config[:handler]}
    send_client_socket(event.to_json)
  end

  def send_warning(check_name, msg)
    event = {"name" => check_name, "status" => 1, "output" => "WARNING: #{msg}", "handler" => config[:handler]}
    send_client_socket(event.to_json)
  end

  def send_critical(check_name, msg)
    event = {"name" => check_name, "status" => 2, "output" => "CRITICAL: #{msg}", "handler" => config[:handler]}
    send_client_socket(event.to_json)
  end

  def send_unknown(check_name, msg)
    event = {"name" => check_name, "status" => 3, "output" => "UNKNOWN: #{msg}", "handler" => config[:handler]}
    send_client_socket(event.to_json)
  end

  def find_interfaces()
    Dir["/sys/class/net/*"].map { |i| File.basename(i) }.reject { |i| i =~ /^lo/ }
  end

  def get_info(interface)
    info = {}

    # https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-class-net
    ["tx_queue_len", "speed", "mtu", "duplex", "carrier", "operstate"].each do |metric|
      if File.exists?("/sys/class/net/#{interface}/#{metric}")
        value = File.read("/sys/class/net/#{interface}/#{metric}").chomp

        case metric
          when "speed", "mtu"
            info[metric] = value.to_i

          when "tx_queue_len"
            info['txqueuelen'] = value.to_i

          when "carrier"
            info[metric] = value.to_i > 0 ? "up" : "down"

          else
            info[metric] =  value
        end
      else
        info[metric] = nil
      end
    end

    info
  end

  def run
    problems = 0

    @interfaces.each do |interface|
      get_info(interface).each do |metric, value|
        check_name = "network-interface-#{interface}-#{metric}"

        if value != nil
          if @json_config.has_key?('interfaces') and @json_config['interfaces'].has_key?(interface) and @json_config['interfaces'][interface].has_key?(metric)
            if value != @json_config['interfaces'][interface][metric]
              msg = "Expected #{metric} #{@json_config['interfaces'][interface][metric]} but found #{value} on #{interface}"
              if config[:warn]
                send_warning(check_name, msg)
              else
                send_critical(check_name, msg)
              end
              problems += 1
            else
              send_ok(check_name, "Found expected #{metric} (#{@json_config['interfaces'][interface][metric]}) on #{interface}")
            end
          else
            if config[metric.to_sym] != nil
              if value != config[metric.to_sym]
                msg = "Expected #{metric} #{config[metric.to_sym]} but found #{value} on #{interface}"
                if config[:warn]
                  send_warning(check_name, msg)
                else
                  send_critical(check_name, msg)
                end
                 problems += 1
              else
                send_ok(check_name, "Found expected #{metric} (#{config[metric.to_sym]}) on #{interface}")
              end
            else
              send_ok(check_name, "#{metric} #{interface}")
            end
          end
        else
          send_unknown(check_name, "Failed to look up #{metric} on #{interface}")
          problems += 1
        end
      end
    end

    if problems > 0
      message "Found #{problems} problems"
      warning if config[:warn]
      critical
    else
      ok "All interfaces (#{@interfaces.join(', ')}) are matching the specified settings"
    end
  end
end
