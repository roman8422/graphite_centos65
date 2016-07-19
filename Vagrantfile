# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "RomanV/centos65"
  config.vm.hostname = "graphite"
  config.vm.network "private_network", ip: "192.168.33.15"
  graphite_version = ENV['GRAPHITE_RELEASE'].nil? ? '0.9.15' : ENV['GRAPHITE_RELEASE']
  config.vm.provision "shell", inline: "cd /vagrant; GRAPHITE_RELEASE=#{graphite_version} bash ./install.sh"
  config.vbguest.auto_update = false
end
