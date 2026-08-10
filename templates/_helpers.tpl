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
