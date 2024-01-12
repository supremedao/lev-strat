#!/bin/bash
echo "Conducting Static Analysis of contracts using Slither..."
# Fetch the current date in DD_MM_YY format
CURRENT_DATE=$(date +"%d%m%y_%H%M%S")

# Fetch the current git branch name
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

# Concatenate the branch name and date
ANALYSIS_FILENAME="${BRANCH_NAME}_${CURRENT_DATE}.md"

# Analysis directory
ANALYSIS_DIRECTORY="./analysis/"

echo $ANALYSIS_DIRECTORY$ANALYSIS_FILENAME

slither . --checklist > $ANALYSIS_DIRECTORY$ANALYSIS_FILENAME

echo "Analysis stored: ${ANALYSIS_DIRECTORY}${ANALYSIS_FILENAME}"
