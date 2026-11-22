# h3 - MiniMax H3 (Ep41) cho ComfyUI

Cai model cua 2 workflow **02. Character Swap LoRA** va **04. Head Swap LoRA**, kem du bo 27 workflow + anh/video mau Ep41, bang 1 lenh:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/qj365/h3/main/install-minimax-h3.sh)
```

Script cai:

| Thanh phan | Dich |
|---|---|
| ComfyUI-Pixaroma (+ ffmpeg) | `custom_nodes/` |
| `minimax_h3_ref2va_pruned_int8_convrot` (19.5 GB) | `models/diffusion_models/h3/` |
| `qwen3vl_32b_minimax_h3_nvfp4_awq` (text encoder) | `models/text_encoders/` |
| `minimax_h3_video_vae_int8_convrot`, `minimax_h3_audio_vae_fp32` | `models/vae/` |
| LoRA DMAD 4step, character swap, head swap | `models/loras/h3/` |
| 27 workflow Ep41 (file da co thi giu nguyen, `FORCE=1` de ghi de) | `user/default/workflows/` |
| 37 anh/video/audio mau Ep41 | `input/` |

Script chay song song: cap nhat ComfyUI + cai Pixaroma + chep workflow chay nen trong luc tai model (toi da `JOBS=3` file cung luc), cap nhat ComfyUI len ban moi nhat, kiem tra sha256 sau khi tai va tu tai lai file hong.
Tuy chon (`JOBS=3`, `UPDATE_COMFY=0`, `WITH_PIXAROMA=0`, `FORCE=1`, `VERIFY=0`, `DRY_RUN=1`, `COMFY_DIR=...`) nam o dau file script.

```bash
DRY_RUN=1 COMFY_DIR=/workspace/ComfyUI bash <(curl -fsSL https://raw.githubusercontent.com/qj365/h3/main/install-minimax-h3.sh)
```

Chi model cua workflow 02 va 04 duoc tai; cac workflow khac can them model rieng.
