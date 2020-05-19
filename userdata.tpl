#!/usr/bin/env bash

echo "Starting deployment of uerdata"

mkdir -p ${app_path}/conf && \
  echo "api_token = ${api_token}" > ${app_path}/conf/app.conf

echo "Finished running user data script."
