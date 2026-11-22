#!/usr/bin/env bash
#
# install-minimax-h3.sh - Cai dat DUNG cac thanh phan cua 2 workflow Ep41:
#   02. Minimax H3 - Character Swap LoRA
#   04. Minimax H3 - Head Swap LoRA
#
# Chay SAU khi da cai ComfyUI. Chay 1 lenh, khong can tao file:
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/qj365/h3/main/install-minimax-h3.sh)
#
# Script cai:
#   - Cap nhat ComfyUI len ban moi nhat
#   - Node ComfyUI-Pixaroma (+ ffmpeg cho node video)
#   - Model: ref2va int8 (diffusion_models/h3), text encoder Qwen3-VL nvfp4, VAE video int8, VAE audio,
#            LoRA DMAD 4step + character swap + head swap (loras/h3)
#   - Du bo 27 workflow Ep41 vao user/default/workflows + 37 anh/video/audio mau vao input
#
# Bien moi truong (deu tuy chon):
#   COMFY_DIR=/workspace/ComfyUI   Thu muc ComfyUI (mac dinh: tu tim)
#   UPDATE_COMFY=0                 Bo qua buoc cap nhat ComfyUI
#   WITH_PIXAROMA=0                Bo qua cai node Pixaroma
#   FORCE=1                        Ghi de workflow/anh/video mau neu da co (mac dinh: bo qua file da co)
#   VERIFY=0                       Bo qua kiem tra sha256 sau khi tai
#   JOBS=3                         So file model tai song song (mac dinh: 3)
#   H3_REF=main                    Nhanh cua repo qj365/h3
#   DRY_RUN=1                      Chi liet ke, khong tai
#   HF_TOKEN=hf_xxx                Token Hugging Face neu can
#
# Luu y: ref2va int8_convrot can PyTorch cu130.
#

set -Eeuo pipefail

# COMFY_DIR duoc xu ly o phan "tim ComfyUI" ben duoi
UPDATE_COMFY="${UPDATE_COMFY:-1}"
WITH_PIXAROMA="${WITH_PIXAROMA:-1}"
FORCE="${FORCE:-0}"
VERIFY="${VERIFY:-1}"
H3_REF="${H3_REF:-main}"
JOBS="${JOBS:-3}"
DRY_RUN="${DRY_RUN:-0}"

HF="https://huggingface.co/Comfy-Org/MiniMax-H3/resolve/main"
KJ="https://huggingface.co/Kijai/MiniMax-H3-experimental/resolve/main"
AX="https://huggingface.co/Alissonerdx/Minimax-H3-ComfyUI/resolve/main"
H3_RAW="https://raw.githubusercontent.com/qj365/h3/${H3_REF}"
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

ok "ComfyUI: $COMFY_DIR"

PY="python3"
[[ -x "$COMFY_DIR/venv/bin/python" ]] && PY="$COMFY_DIR/venv/bin/python"

# ---------- PyTorch (ref2va int8_convrot can cu130) ----------

TORCH_VER=""
$PY -c 'import torch' 2>/dev/null && TORCH_VER="$($PY -c 'import torch; print(torch.__version__)' 2>/dev/null)"
if [[ -z "$TORCH_VER" ]]; then
  warn "Chua thay PyTorch trong $PY"
elif [[ "$TORCH_VER" == *cu13* ]]; then
  ok "PyTorch $TORCH_VER"
else
  warn "PyTorch $TORCH_VER khong phai cu130 - model int8_convrot co the khong chay"
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

LOGDIR="$(mktemp -d)"
cleanup() { if [[ -n "${LOGDIR:-}" ]]; then rm -rf "$LOGDIR"; fi; }
trap cleanup EXIT

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
    echo x >> "$LOGDIR/total"
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

# ---------- cap nhat ComfyUI ----------

step_update() {
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
}

# ---------- workflow + file mau (tai du bo 27 workflow + 37 file mau, deu nhe) ----------

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

step_workflows() {
  echo
  log "=== Workflow + file mau (qj365/h3@${H3_REF}) ==="
  W="$COMFY_DIR/user/default/workflows"

  if [[ "$DRY_RUN" == "1" ]]; then
    echo "    workflows/*.json (27 file) -> $W"
    echo "    input/*          (37 file) -> $COMFY_DIR/input"
  else
    TMP="$(mktemp -d)"
    log "Tai https://codeload.github.com/qj365/h3/tar.gz/refs/heads/${H3_REF}"
    fetch "https://codeload.github.com/qj365/h3/tar.gz/refs/heads/${H3_REF}" \
      | tar -xz -C "$TMP" --strip-components=1 \
      || { rm -rf "$TMP"; die "Khong tai/giai nen duoc repo qj365/h3 (repo private? sai nhanh H3_REF?)"; }

    copy_dir "$TMP/workflows" "$W"
    copy_dir "$TMP/input" "$COMFY_DIR/input"

    # Workflow luu duong dan model kieu Windows ("h3\\file"), Linux can "h3/file".
    # Sua tren ban da cai (ke ca ban chep o lan chay truoc) cho moi workflow co trong repo.
    if [[ -d "$TMP/workflows" ]]; then
      find "$TMP/workflows" -maxdepth 1 -name '*.json' -print0 | while IFS= read -r -d '' f; do
        if [[ -f "$W/$(basename "$f")" ]]; then
          sed -i 's#"\([A-Za-z0-9_-]*\)\\\\\([^"\\]*\.safetensors"\)#"\1/\2#g' "$W/$(basename "$f")"
        fi
      done
    fi
    rm -rf "$TMP"
  fi
}

# ---------- node ComfyUI-Pixaroma ----------

step_pixaroma() {
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
}

M="$COMFY_DIR/models"
mkdir -p "$M"/{diffusion_models/h3,text_encoders,vae,loras/h3} \
         "$COMFY_DIR/user/default/workflows" "$COMFY_DIR/input"


# ---------- chay song song ----------
# - Chuoi A (nen): cap nhat ComfyUI -> cai Pixaroma (tuan tu vi cung dung pip)
# - Chuoi B (nen): workflow + file mau
# - Model: tai song song toi da $JOBS file; sha256 cua file nay chay trong luc file khac van dang tai
# DRY_RUN hoac bash cu (<4.3, khong co wait -n): chay tuan tu.

PARALLEL=1
if [[ "$DRY_RUN" == "1" ]] || (( BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1] < 403 )); then
  PARALLEL=0
fi
[[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || JOBS=3

bg() { # chay lenh (ham download) song song, gioi han $JOBS tien trinh
  if [[ "$PARALLEL" == "0" ]]; then "$@"; return; fi
  while (( $(jobs -pr | wc -l) >= JOBS )); do wait -n || true; done
  { ( "$@" ) || : > "$LOGDIR/fail"; } &
}

[[ "$DRY_RUN" == "1" ]] && { echo; warn "DRY_RUN=1 - chi liet ke file:"; echo; }

if [[ "$PARALLEL" == "1" ]]; then
  [[ "$UPDATE_COMFY" == "1" || "$WITH_PIXAROMA" == "1" ]] && log "Cap nhat ComfyUI / cai Pixaroma chay nen..."
  {
    (
      [[ "$UPDATE_COMFY" == "1" ]] && step_update
      [[ "$WITH_PIXAROMA" == "1" ]] && step_pixaroma
      true
    ) > "$LOGDIR/a.log" 2>&1 || : > "$LOGDIR/fail_a"
  } &
  { ( step_workflows ) > "$LOGDIR/b.log" 2>&1 || : > "$LOGDIR/fail_b"; } &
else
  [[ "$UPDATE_COMFY" == "1" ]] && step_update
  step_workflows
  [[ "$WITH_PIXAROMA" == "1" ]] && step_pixaroma
fi

# ---------- model ----------
# Duong dan lay tu ghi chu "Download Models" trong chinh 2 workflow.
# Workflow goi model/LoRA theo "h3/<file>" nen phai nam trong thu muc con h3.

echo
log "=== Model ==="
bg download "$HF/diffusion_models/minimax_h3_ref2va_pruned_int8_convrot.safetensors" \
         "$M/diffusion_models/h3/minimax_h3_ref2va_pruned_int8_convrot.safetensors"
bg download "$HF/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors" \
         "$M/text_encoders/qwen3vl_32b_minimax_h3_nvfp4_awq.safetensors"
bg download "$HF/vae/minimax_h3_video_vae_int8_convrot.safetensors" \
         "$M/vae/minimax_h3_video_vae_int8_convrot.safetensors"
bg download "$HF/vae/minimax_h3_audio_vae_fp32.safetensors" \
         "$M/vae/minimax_h3_audio_vae_fp32.safetensors"

echo
log "=== LoRA ==="
bg download "$KJ/loras/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors" \
         "$M/loras/h3/minimax_h3_DMAD_4step_full_lora_avg_rank_39_bf16.safetensors"
bg download "$AX/loras/minimax_h3_character_swap_v1.0_ref2va_r64_gl.safetensors" \
         "$M/loras/h3/minimax_h3_character_swap_v1.0_ref2va_r64_gl.safetensors"
bg download "$AX/loras/minimax_h3_head_swap_v1.0_r32.safetensors" \
         "$M/loras/h3/minimax_h3_head_swap_v1.0_r32.safetensors"

wait   # cho tat ca tien trinh nen

if [[ "$PARALLEL" == "1" ]]; then
  echo
  [[ -s "$LOGDIR/a.log" ]] && cat "$LOGDIR/a.log"
  [[ -s "$LOGDIR/b.log" ]] && cat "$LOGDIR/b.log"
  [[ -e "$LOGDIR/fail_a" ]] && warn "Buoc cap nhat ComfyUI / cai Pixaroma co loi (xem log o tren)"
  [[ -e "$LOGDIR/fail_b" ]] && die "Buoc tai workflow + file mau that bai"
  [[ -e "$LOGDIR/fail" ]] && die "Co file model tai that bai (xem loi o tren). Chay lai script de tiep tuc tai."
fi
TOTAL=0
[[ -s "$LOGDIR/total" ]] && TOTAL="$(wc -l < "$LOGDIR/total")"

# ---------- tong ket ----------

if [[ "$DRY_RUN" == "1" ]]; then
  echo; warn "DRY_RUN - chua tai gi. Bo bien nay de tai that."
  exit 0
fi

echo
ok "Hoan tat ($TOTAL file moi tai)"
echo
du -sh "$M/diffusion_models/h3" "$M/text_encoders" "$M/vae" "$M/loras/h3" 2>/dev/null || true

cat <<EOF

Buoc tiep theo:
  1. Khoi dong lai ComfyUI
  2. Tren trinh duyet bam Ctrl+Shift+R (de nap node Pixaroma)
  3. Workflow > Browse > chon 02. Character Swap LoRA hoac 04. Head Swap LoRA
     (cac workflow con lai can them model rieng - script chi tai model cua 02 va 04)
  4. Node Load CLIP phai de type = minimax
EOF
