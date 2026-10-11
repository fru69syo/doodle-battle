# tflint configuration (run from each root module: `tflint --chdir=envs/prod --config=$(pwd)/.tflint.hcl`).
# The google ruleset checks things `terraform validate` cannot, e.g. invalid machine types or
# regions in string attributes.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "google" {
  enabled = true
  version = "0.40.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

rule "terraform_naming_convention" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}
