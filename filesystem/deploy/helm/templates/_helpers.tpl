{{- define "kv-cache-evictor.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "kv-cache-evictor.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "kv-cache-evictor.eventsServiceName" -}}
{{- include "kv-cache-evictor.fullname" . | trunc 56 | trimSuffix "-" -}}-events
{{- end -}}

{{- define "kv-cache-evictor.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{ include "kv-cache-evictor.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/component: cache-evictor
{{- end -}}

{{- define "kv-cache-evictor.selectorLabels" -}}
app.kubernetes.io/name: {{ include "kv-cache-evictor.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "kv-cache-evictor.configData" -}}
PVC_MOUNT_PATH: {{ .Values.storage.mountPath | quote }}
CACHE_DIRECTORY: {{ .Values.storage.cacheDirectory | quote }}
CLEANUP_THRESHOLD: {{ .Values.settings.cleanupThreshold | quote }}
TARGET_THRESHOLD: {{ .Values.settings.targetThreshold | quote }}
DRY_RUN: {{ .Values.settings.dryRun | quote }}
LOG_LEVEL: {{ .Values.settings.logLevel | quote }}
NUM_CRAWLER_PROCESSES: {{ .Values.settings.numCrawlerProcesses | quote }}
LOGGER_INTERVAL_SECONDS: {{ .Values.settings.loggerIntervalSeconds | quote }}
FILE_QUEUE_MAXSIZE: {{ .Values.settings.fileQueueMaxSize | quote }}
FILE_QUEUE_MIN_SIZE: {{ .Values.settings.fileQueueMinSize | quote }}
DELETION_BATCH_SIZE: {{ .Values.settings.deletionBatchSize | quote }}
DELETION_MAX_FILES_PER_SECOND: {{ .Values.settings.deletionMaxFilesPerSecond | quote }}
FILE_ACCESS_TIME_THRESHOLD_MINUTES: {{ .Values.settings.fileAccessTimeThresholdMinutes | quote }}
HEX_BUCKET_LEN: {{ .Values.settings.hexBucketLen | quote }}
ENABLE_DIR_CLEANUP: {{ .Values.settings.enableDirCleanup | quote }}
DIR_CLEANUP_TTL_SECONDS: {{ .Values.settings.dirCleanupTTLSeconds | quote }}
LOG_FILE_PATH: {{ .Values.settings.logFilePath | quote }}
STORAGE_EVENTS_ENDPOINT: {{ .Values.events.endpoint | quote }}
{{- end -}}

{{- define "kv-cache-evictor.configChecksum" -}}
{{- include "kv-cache-evictor.configData" . | sha256sum -}}
{{- end -}}

{{- define "kv-cache-evictor.image" -}}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) -}}
{{- end -}}

{{- define "kv-cache-evictor.sidecarContainer" -}}
- name: filesystem-evictor
  image: {{ include "kv-cache-evictor.image" . }}
  imagePullPolicy: {{ .Values.image.pullPolicy }}
  securityContext:
    {{- toYaml .Values.containerSecurityContext | nindent 4 }}
  envFrom:
    - configMapRef:
        name: {{ include "kv-cache-evictor.fullname" . }}-settings
  volumeMounts:
    - name: {{ .Values.sidecar.volumeName }}
      mountPath: {{ .Values.storage.mountPath }}
  {{- with .Values.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end -}}
