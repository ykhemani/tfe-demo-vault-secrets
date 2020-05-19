################################################################################
# outputs
output api_key {
  value = data.vault_generic_secret.api_token.data[var.vault_secret_key]
}

output public_ip {
  value = aws_instance.ubuntu.public_ip
}
