#!/usr/bin/env bash
set -euo pipefail

function deploy-and-check() {

  d=$1
 
  # Get the workload name out of the inject yaml and strip whitespace. Gross, but works.
  workload=$(cat ${d}/replay.yaml | grep 'name:' | cut -d ':' -f 2 | xargs)
  replay_ns=$(cat ${d}/namespace.yaml | grep 'name:' | cut -d ':' -f 2 | xargs)

  echo "------"
  echo "Replay: $d"
  echo "Workload name: ${workload}"
  echo "Replay NS: ${replay_ns}"

  # Delete first in case of a previous failed run
  echo "Prep work clean-up $d"
  kubectl delete -f "${d}/namespace.yaml" --wait=true || true
  kubectl apply -k "${d}"

  # We should get the environment id / replay name immediately
  replay_name=$(kubectl get deploy/${workload} -n ${replay_ns} -o jsonpath='{.metadata.annotations.replay\.speedscale\.com/env-id}')
  echo "Replay name: ${replay_name}"
  
  echo "Waiting 7m for replay results to be Ready"
  if kubectl wait --for condition=Ready --timeout=7m replay/${replay_name} -n ${replay_ns}; then
    report_id=$(kubectl get replay/${replay_name} -n ${replay_ns} -o jsonpath='{.status.reportID}')
    echo "Report ID: ${report_id}"
    report=$(speedctl get report ${report_id})
    status=$(echo ${report} | jq -r .report.status)
    echo "Status: ${status}"
  else
    echo "Timed out waiting for report"
    return 1
  fi

  # Once we have either timed out or gotten the report, clean up the namespace
  echo "Cleaning up $d"
  kubectl delete -f "${d}/namespace.yaml" --wait=true || true

  case "${status}" in
      "Complete"|"Missed Goals"|"Passed"|"Stopped")
      return 0
      ;;
      *)
      return 1
  esac
}

# User can optionally define a single replay
replay=${1-entry}
echo "Deploying demo replays"
deploy-and-check "k8s/replays/${replay}"
