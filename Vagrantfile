# Optional: a VM with Docker that runs the whole stack, for machines without Docker.
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/jammy64"
  config.vm.boot_timeout = 600
  config.vm.hostname = "monitoring"
  config.vm.network "private_network", ip: "192.168.56.50"

  config.vm.provider "virtualbox" do |vb|
    vb.linked_clone = true
    vb.memory = 3072
    # More than 1 CPU made VMs hang at boot on a Windows host with Hyper-V enabled.
    vb.cpus = 1
  end

  config.vm.provision "shell", path: "scripts/install-docker.sh"
  # Runs as root: joining the docker group only applies to the vagrant user's next login.
  config.vm.provision "shell", inline: <<-SHELL
    cd /vagrant
    bash scripts/init-secrets.sh
    docker compose up --detach --build --wait
  SHELL
end
