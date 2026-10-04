# 7360

## Server 

```bash
podman build -t image-monserveur ./server7360
```

```bash
podman run --detach --publish 8000:8000 --name container-monserveur image-monserveur
```


## Client

[Install Flutter](https://docs.flutter.dev/install/manual) 

```bash
cd client7360/ 
```

```bash
flutter pub get
```

```bash
flutter run
```
