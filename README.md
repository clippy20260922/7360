# 7360

## Server 

```bash
podman build -t image-monserveur ./server7360
```

```bash
podman run --detach --publish 8000:8000 --name container-monserveur image-monserveur
```
