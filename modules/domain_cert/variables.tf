variable domain_name {
  type = string
  description = "The top lovel domain name of the domain to certify, eg. 'srcoftruth.com'"
}

variable zone_id {
  type = string
  description = "The id of the route53 zone that holds this domain"
}
