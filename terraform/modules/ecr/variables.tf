variable "repositories" {
  type = set(string)
  default = ["web", "was"]
}
variable "name" { type = string }
