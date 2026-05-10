# Variables passed via custom_data from vm.tf
github_token           = node['github_token']
github_user            = node['github_user']
repo_name              = node['github_repo_name']
db_host                = node['db_host']
db_name                = node['db_name']
asana_secret_name      = node['asana_token']
vault_name             = node['vault_name']
db_feedback_table      = node['db_feedback_table']

# Update the package cache
execute 'apt-get update' do
  command 'apt-get update'
  action :nothing
end

# Install Docker
package 'docker.io' do
  action :install
end

# Enable and start Docker service
service 'docker' do
  action [:enable, :start]
end

# Log in to Github Container Registry
execute 'docker-login' do
  command "echo #{github_token} | docker login ghcr.io -u #{github_user} --password-stdin"
  action :run
  sensitive true
end

# Fetch the Asana Token from Key Vault using the VM's Identity
#asana_secret = shell_out!("az keyvault secret show --name 'AsanaToken' --vault-name 'ddg-asana-key' --query value -o tsv").stdout.strip

# Pull and Run the app container
docker_container 'feedback-app' do
  repo "ghcr.io/#{node['github_user']}/feedback-app"
  tag 'latest'
  # Expose port 80 directly from the container to the VM
  port '9999:9999'
  hostname "#{hostname}"
  network_mode 'host'
  restart_policy 'always'
  # Environment variables
  env [
    "DB_HOST=#{db_host}",
    "DB_NAME=#{db_name}",
    "DB_FEEDBACK_TABLE=#{db_feedback_table}",
  ]
end

cron 'daily_reporting_worker' do
  minute '0'
  hour '1'
  # Use --network host so Perl can talk to the Azure IMDS (169.254.169.254) for Managed Identity tokens
  # Pass DB_NAME and DB_HOST to be used by the perl reporting script
  # Pass hostname so that the container's kernel uses it and is accessible to the perl reporting script
  command "docker run --rm --network host --hostname $(hostname) " \
          "-e DB_HOSTNAME=#{db_host}" \
          "-e DB_NAME=#{db_name}" \
          "-e DB_FEEDBACK_TABLE=#{db_feedback_table}"
          "ghcr.io/#{github_user}/#{github_repo_name}/reporting-worker:latest"
  user 'root'
end
