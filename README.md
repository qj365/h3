# h3 - MiniMax H3 + Ep41 cho ComfyUI

Cai model MiniMax H3, node ComfyUI-Pixaroma, workflow Ep41 va anh/video mau len server ComfyUI bang 1 lenh:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qj365/h3/main/install-minimax-h3.sh)
```

Vi du kem tuy chon:

```bash
MODE=all QUANT=int8 COMFY_DIR=/workspace/ComfyUI \
  bash <(curl -fsSL https://raw.githubusercontent.com/qj365/h3/main/install-minimax-h3.sh)
```

Model cho workflow Ep41 (mac dinh `EP41_MODELS=core`: ref2va int8, VAE video int8, LoRA DMAD + character swap + head swap):
dung `EP41_MODELS=all` de tai du bo (them LoRA lms/vfx/style/regenerate, upscaler, pose, Flux Klein), `EP41_MODELS=0` de bo qua.
Script kiem tra sha256 sau khi tai va tu tai lai file hong (tat bang `VERIFY=0`).

Xem truoc, chua tai gi: them `DRY_RUN=1`. Day du bien moi truong nam o dau file `install-minimax-h3.sh`.

## Noi dung

- `install-minimax-h3.sh` - script cai dat
- `workflows/` - 27 workflow Ep41, chep vao `ComfyUI/user/default/workflows`
- `input/` - anh/video/audio mau, chep vao `ComfyUI/input`
