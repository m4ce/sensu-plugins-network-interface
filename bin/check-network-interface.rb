#!/usr/bin/env ruby
#
# check-network-interface.rb
#
# Author: Matteo Cerutti <matteo.cerutti@hotmail.co.uk>
#

require 'sensu-plugin/check/cli'
require 'socket'
require 'json'

class CheckNetworkInterface < Sensu::Plugin::Check::CLI
  option :interface,
         :description => "Comma separated list of interfaces to check (default: ALL)",
         :short => "-i <INTERFACES>",
         :long => "--interface <INTERFACES>",
         :proc => proc { |a| a.split(',') },
         :default => []

  option :ignore_interface,
         :description => "Comma separated list of interfaces to ignore",
         :short => "-x <INTERFACES>",
         :long => "--ignore-interface <INTERFACES>",
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

  option :handlers,
         :description => "Comma separated list of handlers",
         :long => "--handlers <HANDLER>",
         :proc => proc { |s| s.split(',') },
         :default => []

  option :warn,
         :description => "Warn instead of throwing a critical failure",
         :short => "-w",
         :long => "--warn",
         :boolean => true,
         :default => false

  option :dryrun,
         :description => "Do not send events to sensu client socket",
         :long => "--dryrun",
         :boolean => true,
         :default => false

  def initialize()
    super
    
    @ifcfg_dir = nil
    # RHEL
    if File.directory?("/etc/sysconfig/network-scripts")
      @ifcfg_dir = "/etc/sysconfig/network-scripts"
    # SuSE
    elsif File.directory?("/etc/sysconfig/network")
      @ifcfg_dir = "/etc/sysconfig/network"
    end
    
    @interfaces = []
    find_interfaces().each do |intf|
      if config[:ignore_interface].size > 0
        b = false
        config[:ignore_interface].each do |ignore_interface|
          if intf.match(ignore_interface)
            b = true
            break
          end
        end
        next if b
      end

      if config[:interface].size > 0
        b = true
        config[:interface].each do |interface|
          if intf.match(interface)
            b = false
            break
          end
        end
        next if b
      end

      @interfaces << intf
    end

    @json_config = {}
    if File.exists?(config[:config_file])
      @json_config = JSON.parse(File.read(config[:config_file]))
    end

    @interfaces.each do |interface|
      # some interfaces, e.g. loopback devices, always use specific settings
      if interface =~ /^lo(\d+)?/
        @json_config['interfaces'] ||= {}
        @json_config['interfaces'][interface] ||= {}
        @json_config['interfaces'][interface]['mtu'] = 65536 unless @json_config['interfaces'][interface].has_key?('mtu')
        @json_config['interfaces'][interface]['operstate'] = "unknown" unless @json_config['interfaces'][interface].has_key?('operstate')
        @json_config['interfaces'][interface]['txqueuelen'] = 0 unless @json_config['interfaces'][interface].has_key?('txqueuelen')
      end
    end
  end

  def send_client_socket(data)
    if config[:dryrun]
      puts data.inspect
    else
      sock = UDPSocket.new
      sock.send(data + "\n", 0, "127.0.0.1", 3030)
    end
  end

  def send_ok(check_name, msg)
    event = {"name" => check_name, "status" => 0, "output" => "#{self.class.name} OK: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_warning(check_name, msg)
    event = {"name" => check_name, "status" => 1, "output" => "#{self.class.name} WARNING: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_critical(check_name, msg)
    event = {"name" => check_name, "status" => 2, "output" => "#{self.class.name} CRITICAL: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

  def send_unknown(check_name, msg)
    event = {"name" => check_name, "status" => 3, "output" => "#{self.class.name} UNKNOWN: #{msg}", "handlers" => config[:handlers]}
    send_client_socket(event.to_json)
  end

find_interfaces

  def get_info(interface)
    info = {}

    # https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-class-net
    ["tx_queue_len", "speed", "mtu", "duplex", "carrier", "operstate"].each do |metric|
      if File.exists?("/sys/class/net/#{interface}/#{metric}")
        begin
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
        rescue
          info[metric] = nil
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
      ifcfg = nil

      if @ifcfg_dir
        if File.exists?("#{@ifcfg_dir}/ifcfg-#{interface}")
          ifcfg = "#{@ifcfg_dir}/ifcfg-#{interface}"
        end
      end

      interface_config = {}
      if ifcfg
        File.read(ifcfg).split("\n").reject { |i| i =~ /^#/ or i =~ /^\s*$/ }.each do |i|
          k, v = i.split('=')

          metric = k.downcase
          case metric
            when 'mtu', 'txqueuelen'
              value = v.to_i

            else
              value = v
          end
          interface_config[metric] = value
        end
      end

      get_info(interface).each do |metric, value|
        check_name = "network-interface-#{interface}-#{metric}"

        if value != nil
          if interface_config.has_key?(metric)
            if value != interface_config[metric]
              msg = "Expected #{metric} #{interface_config[metric]} but found #{value} on #{interface}"
              if config[:warn]
                send_warning(check_name, msg)
              else
                send_critical(check_name, msg)
              end
              problems += 1
            else
              send_ok(check_name, "Found expected #{metric} (#{interface_config[metric]}) on #{interface}")
            end
          elsif @json_config.has_key?('interfaces') and @json_config['interfaces'].has_key?(interface) and @json_config['interfaces'][interface].has_key?(metric)
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
              send_ok(check_name, "Not monitoring #{metric} on #{interface}")
            end
          end
        #else
        #  send_unknown(check_name, "Failed to look up #{metric} on #{interface}")
        #  problems += 1
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
