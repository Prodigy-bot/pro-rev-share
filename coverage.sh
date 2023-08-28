#!/bin/bash
forge coverage --report lcov
genhtml lcov.info -o coverage --branch-coverage
