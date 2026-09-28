# Docker metadata and service identity

Applications should log to stdout/stderr. Add stable, low-cardinality labels:

```yaml
labels:
  observability.app: my-app
  observability.service: backend
environment:
  OTEL_SERVICE_NAME: my-app-backend
  OTEL_RESOURCE_ATTRIBUTES: service.namespace=my-app,deployment.environment.name=production
```

Compose project/service metadata is also retained when available. Do not use request, user, order, session, or unbounded URL values as metrics or log labels. Applications need no special observability Docker network.
