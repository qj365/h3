#!/usr/bin/env bash
#
# install-minimax-h3.sh - Tai model MiniMax H3 cho ComfyUI
#
# Chay SAU khi da cai ComfyUI.
#
#   chmod +x install-minimax-h3.sh
#   ./install-minimax-h3.sh
#
# Bien moi truong:
#   COMFY_DIR=/root/ComfyUI    Thu muc ComfyUI (mac dinh: ~/ComfyUI)
#   MODE=i2v|r2v|all           Che do (mac dinh: i2v, gom ca T2V)
#   QUANT=auto|int8|fp8|bf16   Bien the diffusion (mac dinh: auto theo PyTorch)
#   ENCODER=nvfp4|int8|bf16    Bien the text encoder (mac dinh: nvfp4)
#   WITH_EMBEDDINGS=1          Tai them 10 embedding hieu ung
#   EP41_MODELS=core|all|0     Model cho workflow Ep41 (mac dinh: core)
#                                core = ref2va int8 (diffusion_models/h3), VAE video int8,
#                                       LoRA DMAD 4step + character swap + head swap (loras/h3)
#                                all  = core + LoRA lms/vfx/style/regenerate2k, RealESRGAN,
#                                       latent upscaler, controlnet pose, SDPose, Flux Klein
#   VERIFY=0                   Bo qua kiem tra sha256 sau khi tai (mac dinh: kiem tra)
#   UPDATE_COMFY=0             Bo qua buoc cap nhat ComfyUI len ban moi nhat
#   WITH_PIXAROMA=0            Bo qua cai node ComfyUI-Pixaroma
#   WITH_EP41=0                Bo qua tai workflow + anh/video mau Ep41 tu repo qj365/h3
#   FORCE=1                    Ghi de workflow/input Ep41 neu da co (mac dinh: bo qua)
#   H3_REF=main                Nhanh cua repo qj365/h3 de tai workflow
#   DRY_RUN=1                  Chi liet ke, khong tai
#   HF_TOKEN=hf_xxx            Token Hugging Face neu can
#
# Ghi chu ve QUANT:
#   int8_convrot  - tot nhat, CAN PyTorch cu130
#   fp8_scaled    - dung khi khong co cu130
#   bf16          - ~40GB, chi hop GPU >= 48GB
#

set -Eeuo pipefail

# COMFY_DIR duoc xu ly o phan "tim ComfyUI" ben duoi
MODE="${MODE:-i2v}"
QUANT="${QUANT:-auto}"
ENCODER="${ENCODER:-nvfp4}"
WITH_EMBEDDINGS="${WITH_EMBEDDINGS:-0}"
EP41_MODELS="${EP41_MODELS:-core}"
VERIFY="${VERIFY:-1}"
UPDATE_COMFY="${UPDATE_COMFY:-1}"
WITH_PIXAROMA="${WITH_PIXAROMA:-1}"
WITH_EP41="${WITH_EP41:-1}"
FORCE="${FORCE:-0}"
H3_REF="${H3_REF:-main}"
DRY_RUN="${DRY_RUN:-0}"

HF="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main"
TPL="https://raw.githubusercontent.com/Comfy-Org/workflow_templates/main"
KJ="https://huggingface.co/Kijai/MiniMax-H3-experimental/resolve/main"
AX="https://huggingface.co/Alissonerdx/Minimax-H3-ComfyUI/resolve/main"
H3_TARBALL="https://codeload.github.com/qj365/h3/tar.gz/refs/heads/${H3_REF}"
PIXAROMA_URLS=(https://gitlab.com/pixaroma/comfyui-pixaroma.git
               https://github.com/pixaroma/ComfyUI-Pixaroma.git)

log()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'die "Loi tai dong $LINENO"' ERR

# ---------- tim ComfyUI ----------

is_comfy() { [[ -f "$1/main.py" ]] && [[ -d "$1/comfy" ]]; }

find_comfy() {
  local c

  # 1. Nguoi dung chi dinh ro -> ton trong tuyet doi
  if [[ -n "${COMFY_DIR_SET:-}" ]]; then
    is_comfy "$COMFY_DIR" && { echo "$COMFY_DIR"; return 0; }
    return 1
  fi

  # 2. Cac vi tri hay gap
  for c in "$HOME/ComfyUI" "$PWD/ComfyUI" "$PWD" \
           /workspace/ComfyUI /opt/ComfyUI /root/ComfyUI \
           /content/ComfyUI /data/ComfyUI /app/ComfyUI \
           "$HOME/comfy/ComfyUI" /workspace/comfy/ComfyUI; do
    is_comfy "$c" && { echo "$c"; return 0; }
  done

  # 3. Suy tu tien trinh dang chay
  local pid_main
  pid_main="$(ps -eo args= 2>/dev/null | grep -m1 '[m]ain\.py' || true)"
  if [[ -n "$pid_main" ]]; then
    local p; p="$(echo "$pid_main" | grep -o '[^ ]*main\.py' | head -1)"
    [[ -n "$p" ]] && { p="$(dirname "$p")"; is_comfy "$p" && { echo "$p"; return 0; }; }
  fi

  # 4. Quet dia, gioi han do sau de khong treo
  for base in "$HOME" /workspace /opt /data /mnt; do
    [[ -d "$base" ]] || continue
    c="$(find "$base" -maxdepth 4 -name main.py -type f 2>/dev/null \
         | while read -r f; do
             d="$(dirname "$f")"; is_comfy "$d" && { echo "$d"; break; }
           done | head -1)"
    [[ -n "$c" ]] && { echo "$c"; return 0; }
  done

  return 1
}

# Ghi nhan neu nguoi dung tu dat COMFY_DIR
[[ -n "${COMFY_DIR+x}" ]] && COMFY_DIR_SET=1
COMFY_DIR="${COMFY_DIR:-$HOME/ComfyUI}"

if ! is_comfy "$COMFY_DIR"; then
  log "Dang tim ComfyUI..."
  FOUND="$(find_comfy || true)"
  if [[ -n "$FOUND" ]]; then
    COMFY_DIR="$FOUND"
    ok "Tim thay: $COMFY_DIR"
  else
    die "Khong tim thay ComfyUI.
Da thu: ~/ComfyUI, ./ComfyUI, /workspace, /opt, /root, /content, /data, /app
Chi dinh thu cong: COMFY_DIR=/duong/dan/ComfyUI ./install-minimax-h3.sh"
  fi
fi

case "$MODE" in i2v|t2v|r2v|all) ;; *) die "MODE khong hop le: $MODE" ;; esac
[[ "$MODE" == "t2v" ]] && MODE="i2v"   # cung model, i2v lam duoc ca t2v

ok "ComfyUI: $COMFY_DIR"

# ---------- doc GPU ----------

VRAM=0
if command -v nvidia-smi >/dev/null 2>&1; then
  VRAM="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo 0)"
  GPU="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo '?')"
  ok "GPU: $GPU (${VRAM} MiB)"
fi

# ---------- chon bien the diffusion ----------

PY="python3"
[[ -x "$COMFY_DIR/venv/bin/python" ]] && PY="$COMFY_DIR/venv/bin/python"

TORCH_VER=""
$PY -c 'import torch' 2>/dev/null && TORCH_VER="$($PY -c 'import torch; print(torch.__version__)' 2>/dev/null)"

if [[ "$QUANT" == "auto" ]]; then
  if [[ -z "$TORCH_VER" ]]; then
    warn "Chua thay PyTorch, mac dinh chon fp8_scaled cho an toan"
    QUANT="fp8"
  elif [[ "$TORCH_VER" == *cu13* ]]; then
    QUANT="int8"
    ok "PyTorch $TORCH_VER -> dung int8_convrot (ban tot nhat)"
  else
    QUANT="fp8"
    warn "PyTorch $TORCH_VER khong phai cu130 -> dung fp8_scaled"
    warn "Muon dung int8_convrot: cai lai PyTorch cu130 roi chay lai voi QUANT=int8"
  fi
fi

case "$QUANT" in
  int8) SUFFIX="pruned_int8_convrot" ;;
  fp8)  SUFFIX="pruned_fp8_scaled"   ;;
  bf16) SUFFIX="pruned_bf16"
        [[ "$VRAM" -gt 0 && "$VRAM" -lt 45000 ]] && \
          warn "pruned_bf16 khoang 40GB, GPU ban co ${VRAM} MiB - se phai offload nhieu" ;;
  *)    die "QUANT khong hop le: $QUANT (int8 / fp8 / bf16)" ;;
esac

case "$ENCODER" in
  nvfp4) ENC_FILE="qwen3vl_32b_minimax_h3_nvfp4_awq" ;;
  int8)  ENC_FILE="qwen3vl_32b_minimax_h3_int8_convrot" ;;
  bf16)  ENC_FILE="qwen3vl_32b_minimax_h3_bf16" ;;
  *)     die "ENCODER khong hop le: $ENCODER" ;;
esac

log "Diffusion:    *_${SUFFIX}"
log "Text encoder: ${ENC_FILE}"
log "Che do:       ${MODE}"

# ---------- cap nhat ComfyUI ----------

if [[ "$UPDATE_COMFY" == "1" ]]; then
  echo
  log "=== Cap nhat ComfyUI ==="
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    git pull (nhanh master) + pip install -r requirements.txt"
  elif ! command -v git >/dev/null 2>&1 || [[ ! -d "$COMFY_DIR/.git" ]]; then
    warn "ComfyUI khong phai git clone (hoac thieu git) - bo qua cap nhat"
  else
    export GIT_TERMINAL_PROMPT=0
    OLD_VER="$(git -C "$COMFY_DIR" describe --tags --always 2>/dev/null || echo '?')"
    # Dang o detached HEAD (vd: checkout theo tag stable) -> chuyen ve master de lay ban moi nhat
    if [[ "$(git -C "$COMFY_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)" == "HEAD" ]]; then
      git -C "$COMFY_DIR" checkout -q master 2>/dev/null \
        || warn "Khong chuyen duoc ve nhanh master (co thay doi cuc bo?)"
    fi
    if git -C "$COMFY_DIR" pull --ff-only -q; then
      NEW_VER="$(git -C "$COMFY_DIR" describe --tags --always 2>/dev/null || echo '?')"
      if [[ "$OLD_VER" == "$NEW_VER" ]]; then
        ok "ComfyUI da la ban moi nhat ($NEW_VER)"
      else
        ok "ComfyUI: $OLD_VER -> $NEW_VER"
      fi
      if [[ -f "$COMFY_DIR/requirements.txt" ]]; then
        log "Cap nhat thu vien python cua ComfyUI (khong dong vao torch)"
        $PY -m pip install -q -r "$COMFY_DIR/requirements.txt" 2>/dev/null \
          || $PY -m pip install -q --break-system-packages -r "$COMFY_DIR/requirements.txt" \
          || warn "pip that bai - chay tay: $PY -m pip install -r $COMFY_DIR/requirements.txt"
      fi
    else
      warn "git pull that bai (co thay doi cuc bo hoac nhanh khac master?) - giu ban hien tai ($OLD_VER)"
    fi
  fi
fi

# ---------- cong cu tai ----------

if ! command -v aria2c >/dev/null 2>&1; then
  warn "Khong co aria2c - tai 1 luong, cham hon nhieu tren duong truyen xa"
  if command -v apt-get >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
    log "Dang cai aria2"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq aria2 >/dev/null 2>&1 \
      && ok "Da cai aria2c" || warn "Cai aria2 that bai, dung curl"
  fi
fi

if command -v aria2c >/dev/null 2>&1; then
  DL="aria2c"; ok "Tai bang aria2c (8 luong song song)"
elif command -v curl >/dev/null 2>&1; then
  DL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL="wget"
else
  die "Can aria2c, curl hoac wget"
fi

TOTAL=0

# sha256 goc cua file LFS tren Hugging Face (header x-linked-etag); rong neu khong lay duoc
remote_sha() {
  command -v curl >/dev/null 2>&1 || return 0
  local h=()
  [[ -n "${HF_TOKEN:-}" ]] && h=(-H "Authorization: Bearer $HF_TOKEN")
  curl -sIL "${h[@]}" "$1" 2>/dev/null | tr -d '\r' \
    | awk -F': ' 'tolower($1)=="x-linked-etag"{gsub(/"/,"",$2); print $2; exit}' || true
}

# verify_file <url> <dest> : 0 = dung hoac khong kiem tra duoc, 1 = sai sha256
verify_file() {
  local url="$1" dest="$2" want got
  [[ "$VERIFY" == "1" ]] || return 0
  [[ "$dest" == *.safetensors || "$dest" == *.pth ]] || return 0
  command -v sha256sum >/dev/null 2>&1 || return 0
  [[ -e "$dest.verified" ]] && return 0
  want="$(remote_sha "$url")"
  [[ -n "$want" ]] || return 0
  log "Kiem tra sha256: $(basename "$dest") (file lon, doi chut)"
  got="$(sha256sum "$dest" | cut -d' ' -f1)"
  if [[ "$got" == "$want" ]]; then
    : > "$dest.verified"
    return 0
  fi
  return 1
}

fetch_file() {
  local url="$1" dest="$2" name dir
  name="$(basename "$dest")"; dir="$(dirname "$dest")"
  case "$DL" in
    aria2c)
      local a=()
      [[ -n "${HF_TOKEN:-}" ]] && a=(--header "Authorization: Bearer $HF_TOKEN")
      aria2c -c -x8 -s8 -k1M --console-log-level=warn --summary-interval=15 \
        "${a[@]}" -d "$dir" -o "$name" "$url" \
        || { warn "Dia: $(df -h "$dir" 2>/dev/null | awk 'NR==2{print $4" trong / "$2" ("$5" da dung)"}')"
             die "Tai that bai: $name (neu het dung luong: xoa file khong dung roi chay lai, se tiep tuc tai)"; }
      ;;
    curl)
      local h=()
      [[ -n "${HF_TOKEN:-}" ]] && h=(--header "Authorization: Bearer $HF_TOKEN")
      curl -fL --progress-bar -C - "${h[@]}" -o "$dest.part" "$url" \
        || die "Tai that bai: $name (chay lai script de tiep tuc tai)"
      mv "$dest.part" "$dest" ;;
    wget)
      local w=()
      [[ -n "${HF_TOKEN:-}" ]] && w=(--header="Authorization: Bearer $HF_TOKEN")
      wget -c "${w[@]}" -O "$dest.part" "$url" \
        || die "Tai that bai: $name (chay lai script de tiep tuc tai)"
      mv "$dest.part" "$dest" ;;
  esac
}

download() {
  local url="$1" dest="$2"
  local name dir attempt
  name="$(basename "$dest")"; dir="$(dirname "$dest")"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    $name"
    return 0
  fi

  mkdir -p "$dir"

  # Ban cu cua script de file o thu muc cha (vd diffusion_models/x.safetensors); workflow Ep41 can
  # no trong thu muc con h3/ hoac flux2/ -> chuyen sang do, khong tai them mot ban nua (tiet kiem dia)
  local up
  up="$(dirname "$dir")/$name"
  if [[ ! -s "$dest" && -f "$up" && ! -L "$up" && "$(basename "$dir")" =~ ^(h3|flux2)$ ]]; then
    log "Da co ban o $(dirname "$dir") - chuyen vao $(basename "$dir")/: $name"
    rm -f "$dest" "$dest.aria2"
    mv "$up" "$dest"
    rm -f "$up.verified"
  fi

  # aria2c tao san file day du dung luong (toan so 0) ngay tu dau; file .aria2 con ton tai
  # nghia la tai chua xong -> khong coi la "da co", de aria2c -c tiep tuc tai
  if [[ -s "$dest" && ! -e "$dest.aria2" ]]; then
    if verify_file "$url" "$dest"; then
      ok "Da co: $name ($(du -h "$dest" | cut -f1))"
      return 0
    fi
    warn "File hong (sai sha256): $name - xoa va tai lai"
    rm -f "$dest" "$dest.verified"
  fi
  [[ -e "$dest.aria2" ]] && warn "Tai do dang: $name - tiep tuc tai"

  for attempt in 1 2; do
    log "Tai: $name"
    TOTAL=$((TOTAL + 1))
    fetch_file "$url" "$dest"
    if verify_file "$url" "$dest"; then
      ok "Xong: $name"
      return 0
    fi
    warn "Sai sha256 sau khi tai: $name"
    rm -f "$dest" "$dest.aria2" "$dest.verified"
  done
  die "File van sai sha256 sau 2 lan tai: $name (kiem tra mang/dia, hoac chay VERIFY=0 de bo qua)"
}

M="$COMFY_DIR/models"
mkdir -p "$M"/{diffusion_models,text_encoders,vae,loras,embeddings} \
         "$COMFY_DIR/user/default/workflows" "$COMFY_DIR/input"

[[ "$DRY_RUN" == "1" ]] && { echo; warn "DRY_RUN=1 - chi liet ke file:"; echo; }

# ---------- dung chung ----------

echo
log "=== Dung chung ==="
download "$HF/text_encoders/${ENC_FILE}.safetensors" "$M/text_encoders/${ENC_FILE}.safetensors"
download "$HF/vae/minimax_h3_video_vae_fp16.safetensors" "$M/vae/minimax_h3_video_vae_fp16.safetensors"
download "$HF/vae/minimax_h3_audio_vae_fp32.safetensors" "$M/vae/minimax_h3_audio_vae_fp32.safetensors"

# ---------- diffusion ----------

if [[ "$MODE" == "i2v" || "$MODE" == "all" ]]; then
  echo
  log "=== fl2va (T2V + I2V) ==="
  download "$HF/diffusion_models/minimax_h3_fl2va_${SUFFIX}.safetensors" \
           "$M/diffusion_models/minimax_h3_fl2va_${SUFFIX}.safetensors"
fi

if [[ "$MODE" == "r2v" || "$MODE" == "all" ]]; then
  echo
  log "=== ref2va (R2V) ==="
  if [[ "$SUFFIX" == "pruned_int8_convrot" && "$EP41_MODELS" != "0" ]]; then
    echo "    (dung ban trong diffusion_models/h3 o phan Ep41, tao symlink)"
  else
    download "$HF/diffusion_models/minimax_h3_ref2va_${SUFFIX}.safetensors" \
             "$M/diffusion_models/minimax_h3_ref2va_${SUFFIX}.safetensors"
  fi
fi

# ---------- model cho workflow Ep41 ----------
# Duong dan/thu muc lay tu chinh ghi chu "Download Models" trong cac workflow Ep41.
# Workflow goi model theo "h3/<file>" nen phai nam trong thu muc con h3.

if [[ "$EP41_MODELS" != "0" ]]; then
  echo
  log "=== Ep41 model (${EP41_MODELS}) ==="
  # Diffusion ref2va int8 (can PyTorch cu130)
  download "$HF/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
           "$M/diffusion_models/h3/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
  # VAE video int8 (workflow Ep41 dung ban nay, khac ban fp16 o tren)
  download "$HF/vae/minimax_h3_video_vae_int8_convrot.safetensors" \
           "$M/vae/minimax_h3_video_vae_int8_convrot.safetensors"
  # LoRA
  download "$KJ/loras/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors" \
           "$M/loras/h3/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"
  download "$AX/loras/minimax_h3_character_swap_v1.0_ref2va_r64_gl.safetensors" \
           "$M/loras/h3/minimax_h3_character_swap_v1.0_ref2va_r64_gl.safetensors"
  download "$AX/loras/minimax_h3_head_swap_v1.0_r32.safetensors" \
           "$M/loras/h3/minimax_h3_head_swap_v1.0_r32.safetensors"

  if [[ "$EP41_MODELS" == "all" ]]; then
    download "$AX/loras/minimax_h3_lms_v1.0_r64.safetensors" \
             "$M/loras/h3/minimax_h3_lms_v1.0_r64.safetensors"
    download "$AX/loras/minimax_h3_vfx_edit_v1.0_r128.safetensors" \
             "$M/loras/h3/minimax_h3_vfx_edit_v1.0_r128.safetensors"
    download "$AX/loras/minimax_h3_style_transfer_v1.0_r64.safetensors" \
             "$M/loras/h3/minimax_h3_style_transfer_v1.0_r64.safetensors"
    download "https://huggingface.co/DrakenZA/Open-H3-Regenerate-2K-ComfyUI/resolve/main/open_h3_regenerate_2k_comfy_swiglu_fixed.safetensors" \
             "$M/loras/h3/open_h3_regenerate_2k_comfy_swiglu_fixed.safetensors"
    download "https://huggingface.co/ai-forever/Real-ESRGAN/resolve/main/RealESRGAN_x2.pth" \
             "$M/upscale_models/RealESRGAN_x2.pth"
    download "https://huggingface.co/LBH-123-AI/Minimax_h3_latent_Upscaler/resolve/main/minimax_h3_latent_upscaler_3d_conv_v1/minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors" \
             "$M/latent_upscale_models/minimax_h3_latent_upscaler_3d_conv_v1_fp16.safetensors"
    download "$HF/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors" \
             "$M/model_patches/minimax_h3_fun_controlnet_union_pruned_int8_convrot.safetensors"
    download "https://huggingface.co/Comfy-Org/SDPose/resolve/main/checkpoints/sdpose_wholebody_fp16.safetensors" \
             "$M/checkpoints/sdpose_wholebody_fp16.safetensors"
    download "https://huggingface.co/Comfy-Org/SDPose/resolve/main/diffusion_models/rt_detr_v4-x-hgnet_fp16.safetensors" \
             "$M/diffusion_models/rt_detr_v4-x-hgnet_fp16.safetensors"
    download "https://huggingface.co/Winnougan/Klein9b-Distilled-Base-INT8-Convrot/resolve/main/flux-2-klein-9b-int8-convrot.safetensors" \
             "$M/diffusion_models/flux2/flux-2-klein-9b-int8-convrot.safetensors"
    download "https://huggingface.co/Comfy-Org/flux2-klein-9B/resolve/main/split_files/text_encoders/qwen_3_8b_fp8mixed.safetensors" \
             "$M/text_encoders/qwen_3_8b_fp8mixed.safetensors"
    download "https://huggingface.co/Comfy-Org/flux2-dev/resolve/main/split_files/vae/flux2-vae.safetensors" \
             "$M/vae/flux2-vae.safetensors"
  fi

  # Template Comfy goi ref2va int8 o thu muc goc -> symlink toi ban trong h3/
  R2V_LINK="$M/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
  if [[ "$DRY_RUN" != "1" && ( "$MODE" == "r2v" || "$MODE" == "all" ) ]] \
     && [[ ! -e "$R2V_LINK" || -L "$R2V_LINK" ]]; then
    ln -sf "h3/minimax_h3_ref2va_pruned_int8_convrot.safetensors" "$R2V_LINK"
  fi
fi

# ---------- embeddings ----------

if [[ "$WITH_EMBEDDINGS" == "1" ]]; then
  echo
  log "=== Embeddings (hieu ung) ==="
  for e in art_is_explosion blooming_flowers bullet_time dark_magic fire_breath \
           four_seasons kiss_camera spiral_ascent storm_magic truman_show; do
    download "$HF/embeddings/minimaxh3_${e}.safetensors" \
             "$M/embeddings/minimaxh3_${e}.safetensors"
  done
fi

# ---------- workflow + anh mau ----------

echo
log "=== Workflow ==="
W="$COMFY_DIR/user/default/workflows"

if [[ "$MODE" == "i2v" || "$MODE" == "all" ]]; then
  download "$TPL/templates/video_minimax_h3_t2v.json" "$W/minimax_h3_t2v.json"
  download "$TPL/templates/video_minimax_h3_i2v.json" "$W/minimax_h3_i2v.json"
  download "$TPL/input/transparent_rgb_gaming_mouse.png" "$COMFY_DIR/input/transparent_rgb_gaming_mouse.png"
fi
if [[ "$MODE" == "r2v" || "$MODE" == "all" ]]; then
  download "$TPL/templates/video_minimax_h3_r2v.json" "$W/minimax_h3_r2v.json"
  download "$TPL/input/red_superboy_on_city_roof.png" "$COMFY_DIR/input/red_superboy_on_city_roof.png"
  download "$TPL/input/mecha_dragon_lightning.png" "$COMFY_DIR/input/mecha_dragon_lightning.png"
fi

# ---------- Ep41: workflow + anh/video mau tu repo qj365/h3 ----------

fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1"
  elif command -v wget >/dev/null 2>&1; then wget -qO- "$1"
  else return 1; fi
}

# copy_dir <nguon> <dich> : chi chep file, bo qua file da co tru khi FORCE=1
copy_dir() {
  local src="$1" dst="$2" f n new=0 skip=0
  if [[ ! -d "$src" ]]; then
    warn "Repo khong co thu muc $(basename "$src")"
    return 0
  fi
  mkdir -p "$dst"
  while IFS= read -r -d '' f; do
    n="$(basename "$f")"
    if [[ -e "$dst/$n" && "$FORCE" != "1" ]]; then
      skip=$((skip + 1))
    else
      cp -f "$f" "$dst/$n"
      new=$((new + 1))
    fi
  done < <(find "$src" -maxdepth 1 -type f -print0)
  ok "$(basename "$src") -> $dst  (moi: $new, bo qua vi da co: $skip)"
}

if [[ "$WITH_EP41" == "1" ]]; then
  echo
  log "=== Ep41: workflow + input (qj365/h3@${H3_REF}) ==="
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    workflows/*.json -> $W"
    echo "    input/*          -> $COMFY_DIR/input"
  else
    TMP="$(mktemp -d)"
    log "Tai $H3_TARBALL"
    fetch "$H3_TARBALL" | tar -xz -C "$TMP" --strip-components=1 \
      || { rm -rf "$TMP"; die "Khong tai/giai nen duoc repo qj365/h3 (repo private? sai nhanh H3_REF?)"; }
    # Workflow luu duong dan model kieu Windows ("h3\\file"), Linux can "h3/file"
    if [[ -d "$TMP/workflows" ]]; then
      find "$TMP/workflows" -maxdepth 1 -name '*.json' -print0 \
        | xargs -0 -r sed -i 's#"\([A-Za-z0-9_-]*\)\\\\\([^"\\]*\.safetensors"\)#"\1/\2#g'
    fi
    copy_dir "$TMP/workflows" "$W"
    copy_dir "$TMP/input" "$COMFY_DIR/input"
    rm -rf "$TMP"
  fi
fi

# ---------- node ComfyUI-Pixaroma ----------

if [[ "$WITH_PIXAROMA" == "1" ]]; then
  echo
  log "=== Node ComfyUI-Pixaroma ==="
  CN="$COMFY_DIR/custom_nodes"
  PX="$CN/ComfyUI-Pixaroma"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    ${PIXAROMA_URLS[0]} -> $PX"
  elif ! command -v git >/dev/null 2>&1; then
    warn "Khong co git - bo qua Pixaroma. Cai git roi chay lai, hoac cai qua ComfyUI Manager (tim 'Pixaroma')"
  else
    export GIT_TERMINAL_PROMPT=0
    mkdir -p "$CN"
    PX_OK=0
    if [[ -d "$PX/.git" ]]; then
      log "Da co Pixaroma - cap nhat"
      git -C "$PX" pull --ff-only -q || warn "Cap nhat Pixaroma that bai, giu ban hien tai"
      PX_OK=1
    elif [[ -d "$PX" ]]; then
      ok "Da co Pixaroma (khong phai git clone, giu nguyen): $PX"
      PX_OK=1
    else
      for u in "${PIXAROMA_URLS[@]}"; do
        log "Clone $u"
        if git clone --depth 1 -q "$u" "$PX"; then PX_OK=1; ok "Da cai Pixaroma"; break; fi
        rm -rf "$PX"
        warn "Clone that bai, thu nguon khac"
      done
      [[ "$PX_OK" == "1" ]] || warn "Khong clone duoc Pixaroma - cai tay qua ComfyUI Manager"
    fi

    if [[ "$PX_OK" == "1" && -f "$PX/requirements.txt" ]]; then
      log "Cai thu vien python cua Pixaroma"
      $PY -m pip install -q -r "$PX/requirements.txt" 2>/dev/null \
        || $PY -m pip install -q --break-system-packages -r "$PX/requirements.txt" \
        || warn "pip that bai - cai tay: $PY -m pip install -r $PX/requirements.txt"
    fi

    # Node video cua Pixaroma can ffmpeg (git clone khong tu cai ffmpeg)
    if [[ "$PX_OK" == "1" ]] && ! command -v ffmpeg >/dev/null 2>&1; then
      if command -v apt-get >/dev/null 2>&1 && [[ "$(id -u)" == "0" ]]; then
        log "Dang cai ffmpeg"
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg >/dev/null 2>&1 \
          && ok "Da cai ffmpeg" || warn "Cai ffmpeg that bai - node video Pixaroma co the loi"
      else
        warn "Chua co ffmpeg - node video cua Pixaroma co the loi. Cai: apt-get install ffmpeg"
      fi
    fi
  fi
fi

# ---------- tong ket ----------

if [[ "$DRY_RUN" == "1" ]]; then
  echo; warn "DRY_RUN - chua tai gi. Bo bien nay de tai that."
  exit 0
fi

echo
ok "Hoan tat ($TOTAL file moi)"
echo
du -sh "$M/diffusion_models" "$M/text_encoders" "$M/vae" "$M/loras" 2>/dev/null || true

cat <<EOF

Buoc tiep theo:
  1. Khoi dong lai ComfyUI:  ./run-comfyui.sh
  2. Tren trinh duyet bam Ctrl+Shift+R (de nap node Pixaroma)
  3. Workflow > Browse > chon minimax_h3_* hoac cac workflow Ep41 (01..27)

Thiet lap nen dung:
  - Resolution Selector: Megapixels = 0.98  (ra 1344x768)
    Tranh moc 1.0 - cho ra 1376x768, vuot gioi han cua model
  - Multiple = 32
  - Duration chot theo luoi 17k+5 frame @ 24fps

File dang dung: minimax_h3_*_${SUFFIX}
EOF

if [[ "$WITH_EP41" == "1" && "$MODE" == "i2v" ]]; then
  echo
  warn "Nhieu workflow Ep41 (character swap, head swap...) dung model ref2va."
  warn "Chay lai voi MODE=all de tai them ref2va."
fi

if [[ "$QUANT" == "fp8" ]]; then
  echo
  warn "Ban dang dung fp8_scaled. Ban int8_convrot tot hon nhung can PyTorch cu130."
fi
