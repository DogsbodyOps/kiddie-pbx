# VM Vars
project         = "kiddie-pbx"
subscription_id = "42205d9f-6637-4b6c-9a4a-f9e3a0aa15a0"
tenant_id       = "8c34a907-6f84-4d25-b831-e940e2c2b650"
admin_username  = "azureuser"
public_key      = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINar/i4cU90UZb8T6tu9+1lYnNbTD01B0ve/Ay+L+2aP aaron@aaron-laptop"
allowed_ssh_ips = ["217.155.49.58/32", "2a02:8010:6832:1::/64"]

nsg_security_rules = {
  siptls = {
    priority                = 200
    destination_port_ranges = ["5061"]
    source_address_prefixes = ["0.0.0.0/0"]
  }
  srtp-range = {
    priority                = 210
    protocol                = "Udp"
    destination_port_ranges = ["10000-10199"]
    source_address_prefixes = ["0.0.0.0/0"]
  }
}



# Cloudflare Vars
cloudflare_zone_id = "256922624f16a03125e9294c5290aa0d"