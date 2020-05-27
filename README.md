# Secrets from Vault for our Terraform Runs

When our [Terraform](https://terraform.io) configuration requires sensitive information, such as an API Key or Cloud Credentials, or other sensitive information, that sensitive information may be stored securely or dynamically generated in [HashiCorp](https://hashicorp.com) [Vault](https://vaultproject.io). That sensitive information may then be retrieved for use in the Terraform configuration using the [Vault Provider](https://www.terraform.io/docs/providers/vault/) for Terraform.

In this example, we show how Terraform can retrieve from Vault an API Key and other secrets that may be required at provisioning time.

## Terraform to Vault Communication

We will need to enable communication from the instance where Terraform runs to the Vault cluster (by default, on TCP port 8200).

## Protecting State Files and Plans

Be aware that secrets retrieved from Vault will persist in the Terraform state and in any generated plan files. For this reason, these files should be treated as sensitive and protected accordingly. [Terraform Enterprise](https://www.terraform.io/docs/enterprise/index.html) uses Vault's [Transit Secret Engine](https://www.vaultproject.io/docs/secrets/transit) to encrypt state files and plans and controls access to them via [RBAC](https://www.terraform.io/docs/cloud/users-teams-organizations/index.html). For more information, please see the page on [Data Security](https://www.terraform.io/docs/enterprise/system-overview/data-security.html) in Terraform Enterprise.

## Prequisites

This example requires:

* Vault Cluster accessible by our Terraform workspace.

* A workspace in Terraform Enterprise or Terraform CLI that is configured with environment variables required for provisioning in AWS (e.g. `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`).

## Configuration

### Environment Variables

We will configure some environment variables to facilitate our task.

### Configure Vault

For the purposes of our demo, we will need to configure Vault with:

1. A [Key/Value (KV) Secret Engine](https://www.vaultproject.io/docs/secrets/kv) in which we will store a static secret required by our Terraform code at provisioning time. We can also use an existing KV secrets engine.

2. The **static secret** required by our Terraform code **at provisioning time**.

Note: If a secret is required at run time on the resources that we provision, that resource should be configured to authenticate with Vault and retrieve that secret from Vault.

3. A [policy](https://www.vaultproject.io/docs/concepts/policies) that will allow our Terraform code to read the aforementioned secret, as well as to manage its token.

4. An [AppRole Auth Method](https://www.vaultproject.io/docs/auth/approle) to enable our Terraform code to authenticate with Vault.

5. An AppRole Role tied to the aforementioned policy that our Terraform code to authenticate with Vault.

#### Environment Variables

```
# TFE_SECRET_PATH -- Path to TFE secrets in Vault
export TFE_SECRET_PATH=tfe.home.seva.cafe

# KV_PATH -- KV v2 Secrets Engine Path
export KV_PATH=kv

# SECRET_PATH -- Path to secret
export SECRET_PATH=${KV_PATH}/demo/widget_service

# TOKEN_MGMT_POLICY -- Name of Token Management Policy
export TOKEN_MGMT_POLICY=token_management_policy

# TF_KV_POLICY -- Name of Policy to read certain KV secrets.
export TF_KV_POLICY=tf_demo_kv_policy

# APPROLE_AUTH -- AppRole Auth Method Path
export APPROLE_AUTH=approle

# APPROLE_AUTH_ROLE_NAME -- AppRole Role for our Terraform code to authenticate with Vault
export APPROLE_AUTH_ROLE_NAME=tfe_ws1_role

# TFE_ADDR -- Terraform Enterprise Address. e.g. https://app.terraform.io
export TFE_ADDR=$( \
  vault kv get -field=TFE_ADDR kv/tfe/${TFE_SECRET_PATH} \
)

# TFE_ORG -- Name of your Terraform Enterprise Organization.
export TFE_ORG=$( \
  vault kv get -field=TFE_ORG kv/tfe/${TFE_SECRET_PATH} \
)

# TFE_TEAM_TOKEN -- Terraform Team or Individual Token
export TFE_TEAM_TOKEN=$( \
  vault kv get -field=TFE_TEAM_TOKEN kv/tfe/${TFE_SECRET_PATH} \
)

# TFE_WORKSPACE_NAME -- Terraform workspace where we will run our Terraform code.
export TFE_WORKSPACE_NAME=tfe-demo-vault-secrets

# TF_ROLE_ID_VARIABLE -- Name of Terraform variable for the AppRole Role ID.
export TF_ROLE_ID_VARIABLE=vault_role_id

# TF_SECRET_ID_VARIABLE -- Name of Terraform variable for the AppRole Secret ID.
export TF_SECRET_ID_VARIABLE=vault_secret_id
```

#### Enable the KV v2 Secrets Engine

```
vault secrets enable -path=${KV_PATH} kv-v2
```

#### Write the secret that our Terraform code will consume at provisioning time.

```
vault kv put ${SECRET_PATH} \
  api_key=51f8fda1-5ce6-4d64-9ddb-18baf8767249 \
  service_name=widget
```

#### Write Token Management Policy

```
vault policy write ${TOKEN_MGMT_POLICY} -<<EOF
# Manage token renewal
path "auth/token/create" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
```

#### Write KV read policy.

```
vault policy write ${TF_KV_POLICY} -<<EOF
# Retrieve KV secrets
path "kv/data/demo/*" {
  capabilities = [ "read" ]
}
EOF
```

#### Enable AppRole Auth method.

```
vault auth enable -path=${APPROLE_AUTH} approle
```

#### Configure AppRole Role

```
vault write \
  auth/${APPROLE_AUTH}/role/${APPROLE_AUTH_ROLE_NAME} \
  token_policies="${TF_KV_POLICY},${TOKEN_MGMT_POLICY}"
```

### Configure Terraform Workspace

#### Get Workspace ID

In our example, we will interact with Terraform Enterprise using the API.

Let's retrieve the Workspace ID for our Terraform Workspace. We will need this to configure the variables in our workspace.

```
export WORKSPACE_ID=$(curl -s \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  ${TFE_ADDR}/api/v2/organizations/${TFE_ORG}/workspaces | \
  jq -r ".data[] | select (.attributes.name==\"${TFE_WORKSPACE_NAME}\") | .id")
```

#### Role ID and Secret ID
AppRole Auth is Vault's multifactor authentication for applications. In order for the Terraform workspace to authenticate with Vault using the AppRole auth method, that workspace must be provided the Role ID and Secret ID. This task may be completed in one or more continuous integration (CI) pipelines.

##### Role ID
The CI pipeline that creates the workspace may place the AppRole Role ID. This CI pipeline will have a Vault policy that enables it to read that Role ID and place it in the workspace as a sensitive variable.

###### Get Role ID from Vault
```
export TF_ROLE_ID=$(vault \
  read \
  -format=json \
  auth/${APPROLE_AUTH}/role/${APPROLE_AUTH_ROLE_NAME}/role-id \
  | jq -r .data.role_id)
```

###### Configure Role ID in Terraform
Let's create our JSON payload for setting the Role ID. Note that we are marking the variable `sensitive`.
```
cat <<EOF > payload_role_id.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"${TF_ROLE_ID_VARIABLE}",
      "value":"${TF_ROLE_ID}",
      "category":"terraform",
      "hcl":false,
      "sensitive":true
    }
  }
}
EOF
```

Let's set the variable in Terraform. Note that we are doing a `POST` here to create the variable. If the variable was already in palce, we would do a `PATCH` to update the value for the variable.
```
curl -s \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload_role_id.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

Let's dispose of the JSON payload.

```
rm -f payload_role_id.json
```

##### Secret ID
The CI pipeline that runs the workspace, acting as the trusted orchestrator, may place the AppRole Secret ID.This CI pipeline will have a Vault policy that enables it to generate a Secret ID and set it in the workspace as a sensitive variable.

###### Generate Secret ID in Vault
```
export TF_SECRET_ID=$(vault \
  write -f \
  -format=json \
  auth/${APPROLE_AUTH}/role/${APPROLE_AUTH_ROLE_NAME}/secret-id \
  | jq -r .data.secret_id)
```

###### Configure Secret ID in Terraform
Let's create our JSON payload for setting the Role ID. Note that we are marking the variable `sensitive`.

```
cat <<EOF > payload_secret_id.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"${TF_SECRET_ID_VARIABLE}",
      "value":"${TF_SECRET_ID}",
      "category":"terraform",
      "hcl":false,
      "sensitive":true
    }
  }
}
EOF
```

Let's set the variable in Terraform. Note that we are doing a `POST` here to create the variable. If the variable was already in palce, we would do a `PATCH` to update the value for the variable.

```
curl -s \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload_secret_id.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

Let's dispose of the JSON payload.

```
rm -f payload_secret_id.json
```

### Run Terraform Workspace

#### Additional Terraform Variables
Let's set the `vault_addr` variable to indicate the Vault Cluster address for our Terraform workspace.

```
cat <<EOF > payload.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"vault_addr",
      "value":"${VAULT_ADDR}",
      "category":"terraform",
      "hcl":false,
      "sensitive":false
    }
  }
}
EOF
```

```
curl -s \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

```
rm -f payload.json
```

Let's also set the `vault_secret_path` variable to tell our Terraform code the path for the secret in Vault.

```
cat <<EOF > payload.json
{
  "data": {
    "type":"vars",
    "attributes": {
      "key":"vault_secret_path",
      "value":"${SECRET_PATH}",
      "category":"terraform",
      "hcl":false,
      "sensitive":false
    }
  }
}
EOF
```

```
curl -s \
  --header "Authorization: Bearer $TFE_TEAM_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --request POST \
  --data @payload.json \
  ${TFE_ADDR}/api/v2/workspaces/${WORKSPACE_ID}/vars | jq -r .
```

```
rm -f payload.json
```

This Terraform example code places the secret retrieved from Vault, referenced as `data.vault_generic_secret.api_token.data[var.vault_secret_key]` on the filesystem in an AWS ec2 instance at `/opt/app1/conf/app.conf`. It also outputs this secret for illustration purposes.

In order to use this Terraform code, also set the following variables.

* `vpc_id`
* `subnet_id`
* `ssh_key_name`
* `owner_ip`
* `owner`

We are now ready to run our Terraform Workspace.

This may be done via the Terraform API, via the CLI, via the Web UI, or via a git merge/push, as appropriate.
