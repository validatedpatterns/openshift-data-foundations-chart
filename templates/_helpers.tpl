{{/*
Return the storage class used for ODF OSD volume PVCs.

Uses odf.osd.pvc.storageClassName when set; otherwise selects a platform
default from global.clusterPlatform:

  AWS (or unset) -> gp3-csi
  Azure          -> managed-csi
  GCP            -> standard-csi
*/}}
{{- define "odf.osd.storageClassName" -}}
{{- if .Values.odf.osd.pvc.storageClassName -}}
{{- .Values.odf.osd.pvc.storageClassName -}}
{{- else -}}
{{- $platform := .Values.global.clusterPlatform | default "" | lower -}}
{{- if or (eq $platform "") (eq $platform "aws") -}}
gp3-csi
{{- else if eq $platform "azure" -}}
managed-csi
{{- else if eq $platform "gcp" -}}
standard-csi
{{- else -}}
{{- fail (printf "Set odf.osd.pvc.storageClassName or use a supported global.clusterPlatform (AWS, Azure, GCP); got %q" .Values.global.clusterPlatform) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Bash script used by the label-storage-nodes Job and CronJob.
Respects storageSystem.inventory.useSpecificNodes vs nodeJobLabelSelector.
*/}}
{{- define "odf.labelStorageNodes.script" -}}
# Exit promptly with a nonzero code on SIGTERM so node drains can cancel
# this Job without it being marked successful (see podFailurePolicy).
trap 'echo "Cancelled by SIGTERM; exiting 143 without success"; exit 143' TERM
{{- if .Values.storageSystem.inventory.useSpecificNodes }}
{{- range .Values.storageSystem.inventory.nodes }}
oc label node {{ . }} cluster.ocs.openshift.io/openshift-storage='' --overwrite
{{- end }}
{{- else }}
oc label nodes -l {{ .Values.storageSystem.inventory.nodeJobLabelSelector | squote }} cluster.ocs.openshift.io/openshift-storage='' --overwrite
LABELED_COUNT=$(oc get nodes -l cluster.ocs.openshift.io/openshift-storage --no-headers 2>/dev/null | wc -l)
if [ "$LABELED_COUNT" -lt 3 ]; then
  echo "Error: Only $LABELED_COUNT node(s) were labeled. At least 3 nodes must be labeled."
  exit 1
fi
echo "Successfully labeled $LABELED_COUNT node(s)"
{{- end }}
{{- end }}

{{/*
Pod spec shared by the label-storage-nodes Job and CronJob.
*/}}
{{- define "odf.labelStorageNodes.podSpec" -}}
containers:
- image: {{ .Values.job.image }}
  command:
  - /bin/bash
  - -c
  - |
    {{- include "odf.labelStorageNodes.script" . | nindent 4 }}
  name: label-storage-nodes
dnsPolicy: ClusterFirst
restartPolicy: Never
serviceAccountName: {{ .Values.serviceAccountName }}
terminationGracePeriodSeconds: 60
{{- end }}

{{/*
Bash script used by the wait-for-mcp Job. Waits for each configured
MachineConfigPool to finish reconciling (Updated=True) and fails if any
pool is Degraded. This gates StorageCluster creation so Ceph monitor
formation does not race an MCO rolling reboot triggered by node labeling.
*/}}
{{- define "odf.waitForMcp.script" -}}
set -euo pipefail
# Exit promptly with a nonzero code on SIGTERM so node drains can cancel
# this Job without it ever being marked successful. Evictions carry a
# DisruptionTarget condition and are ignored by podFailurePolicy, so a
# cancelled pod does not count against backoffLimit and a replacement
# pod is created to resume the wait.
trap 'echo "Cancelled by SIGTERM; exiting 143 without success"; exit 143' TERM
{{- range .Values.waitForMcp.pools }}
echo "Waiting for MachineConfigPool {{ . }} to finish updating..."
# Run oc wait in the background so the SIGTERM trap is not deferred
# behind the (potentially very long) foreground wait.
oc wait machineconfigpool/{{ . }} --for=condition=Updated --timeout={{ $.Values.waitForMcp.timeout }}s &
WAIT_PID=$!
if ! wait "${WAIT_PID}"; then
  echo "Error: MachineConfigPool {{ . }} did not reach Updated within {{ $.Values.waitForMcp.timeout }}s."
  exit 1
fi
DEGRADED=$(oc get machineconfigpool/{{ . }} -o jsonpath='{.status.conditions[?(@.type=="Degraded")].status}')
if [ "$DEGRADED" = "True" ]; then
  echo "Error: MachineConfigPool {{ . }} is Degraded."
  exit 1
fi
echo "MachineConfigPool {{ . }} is updated and healthy."
{{- end }}
echo "All MachineConfigPools reconciled."
{{- end }}

{{/*
Pod spec for the wait-for-mcp Job.
*/}}
{{- define "odf.waitForMcp.podSpec" -}}
containers:
- image: {{ .Values.job.image }}
  command:
  - /bin/bash
  - -c
  - |
    {{- include "odf.waitForMcp.script" . | nindent 4 }}
  name: wait-for-mcp
dnsPolicy: ClusterFirst
restartPolicy: Never
serviceAccountName: {{ .Values.serviceAccountName }}
terminationGracePeriodSeconds: 60
{{- end }}
