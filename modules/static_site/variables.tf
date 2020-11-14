variable domain_name {
  type = string
  description = "The domain name of the domain to certify, eg. 'srcoftruth.com', eg. 'preview.zyghost.com'"
}

variable zone_id {
  type = string
  description = "The id of the route53 zone that holds this domain"
}
