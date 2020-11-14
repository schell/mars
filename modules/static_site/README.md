# static_site
Defines a static(ish) website where static files are served by cloudfront
* static files are kept in an aws s3 bucket
* requests are served by aws cloudfront
* creates route53 records for one fully qualified domain name, eg "preview.zyghost.com"
* creates an SSL cert for that one domain
