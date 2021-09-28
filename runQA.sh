#!/bin/bash
echo ${RUN_SUITES}
if [ -z "$RUN_SUITES" ]; then
  exit 0
fi
# Send the request to qa-e2e
loop=true
BUILD_RUN=buildrun.json
BUILD_RESULT=buildresult.json
BUILD_ARTIFACTS=buildartifacts.json
circleci_endpoint=https://circleci.com/api/v1.1/project/github/mycsHQ/qa-e2e/
mkdir -p bin/json

curl -s -X POST --header "Content-Type: application/json" -d '{
  "build_parameters": {
    "configurator_branch": "'"$CIRCLE_BRANCH"'",
    "suites": "'"$RUN_SUITES"'"
  }
}
' $circleci_endpoint?circle-token=$QA_TOKEN > $BUILD_RUN

BUILD_NUMBER=`awk '/^\ \ "build_num"/{print $3}' $BUILD_RUN | sed 's/.$//'`

if [ -z "$BUILD_NUMBER" ]
then
  echo "Invalid \$BUILD_NUMBER: $BUILD_NUMBER"
  cat $BUILD_RUN
  exit 1
fi

APIFAIL=0
while $loop; do
  sleep 5
  curl $circleci_endpoint$BUILD_NUMBER?circle-token=$QA_TOKEN > $BUILD_RESULT
  current_status=`awk '/^\ \ "status"/{print $3}' $BUILD_RESULT | sed 's/.$//'`

  if [[ $current_status == '"success"' ]] || [[ $current_status == '"fixed"' ]]
  then
    loop=false
  elif [[ $current_status == '"canceled"' ]] || [[ $current_status == '"failed"' ]]
  then
    loop=false
    echo "Last build status: https://circleci.com/gh/mycsHQ/qa-e2e/"$BUILD_NUMBER "was: "$current_status
  elif [[ $current_status == '"running"' ]] || [[ $current_status == '"queued"' ]] || [[ $current_status == '"not_running"' ]]
  then
    loop=true
  elif ((APIFAIL > 3))
  then
    echo "I can't get build status link: https://circleci.com/gh/mycsHQ/qa-e2e/"$BUILD_NUMBER
    cat $BUILD_RESULT
    exit 1
  else
    echo "I can't get build status link: https://circleci.com/gh/mycsHQ/qa-e2e/"$BUILD_NUMBER
    loop=true
    ((APIFAIL++))
  fi
done

if [ -n "$CI_PULL_REQUEST" ]; then
  npm i request request-promise node-fetch
  node bin/download-results.js $BUILD_NUMBER $QA_TOKEN
  node bin/parse-results.js $MYCSDEVOPS_GITHUB_TOKEN $CI_PULL_REQUEST $BUILD_NUMBER
fi

if [[ $current_status == '"success"' ]] || [[ $current_status == '"fixed"' ]]
then
  exit 0
fi

exit 1
