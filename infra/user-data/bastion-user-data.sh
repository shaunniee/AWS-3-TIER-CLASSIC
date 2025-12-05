#!/bin/bash
set -xe

dnf update -y

# Tools for debugging
dnf install -y postgresql htop telnet bind-utils

# No services to start; this just makes bastion useful for psql and network checks
