#!/bin/sh

# Xcode Cloud post-clone script
# This script runs after Xcode Cloud clones your repository

set -e

echo "Starting Xcode Cloud post-clone setup..."

# Set up any environment variables if needed
# export API_BASE_URL="https://cokeep-api-staging.herokuapp.com"

# Install any additional dependencies
# (SwiftPM dependencies are handled automatically by Xcode Cloud)

# You can add steps here like:
# - Generating mock data
# - Setting up test databases
# - Downloading test fixtures

echo "Xcode Cloud post-clone setup completed successfully!"
