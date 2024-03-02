# Project Name: Using AWS Systems Manager Parameter Store to Manage Elastic Beanstalk Environment Variables

## Description:
This project provides a solution for loading environment variables into Elastic Beanstalk environments from AWS Systems Manager Parameter Store. It includes a Bash script that seamlessly integrates with Elastic Beanstalk's deployment process, dynamically fetching configuration parameters from Parameter Store and injecting them as environment variables into the application environment.

## Usage:
1. Place the provided script (`01_map_parameters_store_to_env_vars.sh`) within the `.platform/hooks/postdeploy` directory of your Elastic Beanstalk application.
2. Ensure that your Elastic Beanstalk environment properties include a `parameter_store_path` specifying the path prefix for your AWS Systems Manager parameters.
3. Deploy your application as usual. The script will execute post-deployment and handle the retrieval and injection of environment variables from Parameter Store.

## Dependencies:
- AWS CLI
- jq (a lightweight and flexible command-line JSON processor)

## Notes:
- Ensure that the IAM role associated with your Elastic Beanstalk environment has the necessary permissions to access AWS Systems Manager Parameter Store.
- Make sure that the AWS CLI is configured with appropriate credentials and region settings.

## Contributing:
Contributions, bug reports, and feature requests are welcome. Feel free to submit pull requests or open issues on the GitHub repository.
