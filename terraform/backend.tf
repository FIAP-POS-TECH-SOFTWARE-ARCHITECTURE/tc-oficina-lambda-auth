terraform {
  backend "s3" {
    bucket       = "tc-fiap-oficina-tfstate-076155200589"
    region       = "us-east-1"
    use_lockfile = true
    # key definida via -backend-config no init:
    # fase-3/lambda-auth-homolog.tfstate | fase-3/lambda-auth-prod.tfstate
  }
}
