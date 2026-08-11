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
terminationGracePeriodSeconds: 400
{{- end }}
