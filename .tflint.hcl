plugin "terraform" {
  enabled = true
  preset = "recommended"
}
rule "terraform_unused_declarations" {
  enabled = false # Shared profile declarations are deliberately available in every isolated stack.
}
