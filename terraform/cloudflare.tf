# Will require to define a cloudflare api key
# You can set it using the CLOUDFLARE_API_TOKEN environment variable

provider "cloudflare" {
}

variable "cloudflare_zone_id" {
  type = string
}

resource "cloudflare_dns_record" "kiddie-pbx" {
  zone_id = var.cloudflare_zone_id
  name    = "kiddie-pbx"
  type    = "A"
  content = module.vm.public_ip
  ttl     = 3600
}

output "cloudflare_dns_record" {
  value = cloudflare_dns_record.kiddie-pbx.name
}