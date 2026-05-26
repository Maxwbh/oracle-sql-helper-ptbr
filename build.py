#!/usr/bin/env python3
"""
build.py — Build, propagação e empacotamento das oracle-sql-helper-ptbr
M&S do Brasil LTDA — contato@msbrasil.inf.br

Uso:
    python build.py                    # empacota todas as skills
    python build.py --skill oracle-dba-ptbr   # empacota só uma
    python build.py --check            # verifica consistência sem empacotar
    python build.py --checksums        # gera checksums dos .skill em dist/

O que este script faz:
    1. Propaga shared/ → cada skill que declara dependência
    2. Valida frontmatter (quick_validate)
    3. Empacota cada skill → dist/*.skill
    4. Gera dist/checksums.sha256

Estrutura esperada:
    oracle-sql-helper-ptbr/
    ├── build.py              (este arquivo)
    ├── marketplace.yml
    ├── shared/               (fontes únicas da verdade)
    │   ├── references/
    │   └── assets/
    ├── skills/
    │   ├── oracle-dba-ptbr/
    │   │   ├── SKILL.md
    │   │   ├── manifest.yml  (declara dependências de shared/)
    │   │   ├── assets/
    │   │   └── references/
    │   └── ...
    └── dist/                 (gerado por este script)
"""

from __future__ import annotations

import argparse
import hashlib
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

import yaml

ROOT      = Path(__file__).parent.resolve()
SKILLS    = ROOT / "skills"
SHARED    = ROOT / "shared"
DIST      = ROOT / "dist"
BUILD_TMP = ROOT / ".build_tmp"

# Cores
_TTY = sys.stdout.isatty()
G = "\033[92m" if _TTY else ""
Y = "\033[93m" if _TTY else ""
R = "\033[91m" if _TTY else ""
C = "\033[96m" if _TTY else ""
B = "\033[1m"  if _TTY else ""
Z = "\033[0m"  if _TTY else ""

def log(msg: str)  -> None: print(msg)
def ok(msg: str)   -> None: print(f"  {G}✅ {msg}{Z}")
def warn(msg: str) -> None: print(f"  {Y}⚠  {msg}{Z}")
def err(msg: str)  -> None: print(f"  {R}❌ {msg}{Z}")
def sep()          -> None: print(f"  {'─'*52}")


# ─── Manifest de cada skill ───────────────────────────────────────────────────

def ler_manifest(skill_dir: Path) -> dict:
    """
    Lê manifest.yml da skill para saber o que importar de shared/.
    Se não existir, retorna manifest vazio (sem dependências shared/).

    Formato do manifest.yml:
        shared:
          references:
            - data-dictionary-ptbr.md
            - plsql-trivadis-guidelines.md
          assets:
            - oracle_devops_utils.py
    """
    manifest_path = skill_dir / "manifest.yml"
    if not manifest_path.exists():
        return {"shared": {"references": [], "assets": []}}
    with open(manifest_path) as f:
        return yaml.safe_load(f) or {}


# ─── Propagação de shared/ ────────────────────────────────────────────────────

def propagar_shared(skill_dir: Path, build_dir: Path) -> list[str]:
    """
    Copia arquivos de shared/ para a skill no diretório de build.
    Retorna lista de arquivos propagados.
    """
    manifest  = ler_manifest(skill_dir)
    shared_cfg = manifest.get("shared", {})
    propagados: list[str] = []

    for ref in shared_cfg.get("references", []):
        src = SHARED / "references" / ref
        dst = build_dir / "references" / ref
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            propagados.append(f"shared/references/{ref}")
        else:
            warn(f"shared/references/{ref} — não encontrado")

    for asset in shared_cfg.get("assets", []):
        src = SHARED / "assets" / asset
        dst = build_dir / "assets" / asset
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            propagados.append(f"shared/assets/{asset}")
        else:
            warn(f"shared/assets/{asset} — não encontrado")

    return propagados


# ─── Validação do SKILL.md ────────────────────────────────────────────────────

def validar_skill(skill_dir: Path) -> bool:
    """Roda quick_validate.py do skill-creator. Retorna True se válido."""
    validator = Path("/mnt/skills/examples/skill-creator/scripts/quick_validate.py")
    if not validator.exists():
        # Fallback: validação manual de frontmatter
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.exists():
            return False
        content = skill_md.read_text(encoding="utf-8")
        return content.startswith("---\n") and "name:" in content
    try:
        result = subprocess.run(
            [sys.executable, str(validator), str(skill_dir)],
            capture_output=True, text=True
        )
        return result.returncode == 0 and "valid" in result.stdout.lower()
    except Exception:
        return False


# ─── Empacotamento ────────────────────────────────────────────────────────────

def empacotar_skill(skill_dir: Path) -> Path:
    """
    Monta a skill em BUILD_TMP (com propagação de shared/),
    valida e gera dist/{name}.skill.
    Retorna Path do .skill gerado.
    """
    name     = skill_dir.name
    build_dir = BUILD_TMP / name

    # Limpar e recriar diretório de build
    if build_dir.exists():
        shutil.rmtree(build_dir)
    shutil.copytree(skill_dir, build_dir)

    # Propagar shared/
    propagados = propagar_shared(skill_dir, build_dir)
    if propagados:
        for p in propagados:
            log(f"    {C}↓ propagado:{Z} {p}")

    # Validar
    if not validar_skill(build_dir):
        err(f"Frontmatter inválido em {name}")
        return None

    # Empacotar como .zip renomeado para .skill
    DIST.mkdir(exist_ok=True)
    skill_file = DIST / f"{name}.skill"

    with zipfile.ZipFile(skill_file, "w", zipfile.ZIP_DEFLATED) as zf:
        for arquivo in sorted(build_dir.rglob("*")):
            if arquivo.is_file():
                arcname = name + "/" + str(arquivo.relative_to(build_dir))
                zf.write(arquivo, arcname)

    return skill_file


# ─── Checksums ────────────────────────────────────────────────────────────────

def gerar_checksums() -> Path:
    """Gera dist/checksums.sha256 com SHA-256 de cada .skill."""
    checksums_file = DIST / "checksums.sha256"
    linhas: list[str] = []

    for skill_file in sorted(DIST.glob("*.skill")):
        sha = hashlib.sha256(skill_file.read_bytes()).hexdigest()
        linhas.append(f"{sha}  {skill_file.name}")
        log(f"    {sha[:16]}...  {skill_file.name}")

    checksums_file.write_text("\n".join(linhas) + "\n", encoding="utf-8")
    return checksums_file


# ─── Verificação de consistência ─────────────────────────────────────────────

def verificar(skill_dir: Path) -> list[str]:
    """Verifica consistência da skill sem empacotar. Retorna lista de problemas."""
    problemas: list[str] = []

    # SKILL.md existe?
    skill_md = skill_dir / "SKILL.md"
    if not skill_md.exists():
        problemas.append("SKILL.md não encontrado")
        return problemas

    # Frontmatter válido?
    if not validar_skill(skill_dir):
        problemas.append("Frontmatter inválido")

    # Manifesto: verificar shared/ referenciados existem?
    manifest = ler_manifest(skill_dir)
    for ref in manifest.get("shared", {}).get("references", []):
        if not (SHARED / "references" / ref).exists():
            problemas.append(f"shared/references/{ref} — não existe")
    for asset in manifest.get("shared", {}).get("assets", []):
        if not (SHARED / "assets" / asset).exists():
            problemas.append(f"shared/assets/{asset} — não existe")

    # Clientes reais?
    proibidos = ["IMESC", "Zitrus", "Memora", "Hapvida", "Nexdom"]
    for arquivo in skill_dir.rglob("*.md"):
        conteudo = arquivo.read_text(encoding="utf-8", errors="ignore")
        for termo in proibidos:
            if termo.lower() in conteudo.lower():
                problemas.append(f"cliente real '{termo}' em {arquivo.name}")

    return problemas


# ─── Ponto de entrada ─────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Build e empacotamento das oracle-sql-helper-ptbr"
    )
    parser.add_argument("--skill", default=None,
                        help="Empacotar apenas esta skill (ex: oracle-dba-ptbr)")
    parser.add_argument("--check", action="store_true",
                        help="Verificar consistência sem empacotar")
    parser.add_argument("--checksums", action="store_true",
                        help="Gerar dist/checksums.sha256")
    args = parser.parse_args()

    log(f"\n{B}{'═'*55}{Z}")
    log(f"{B}  oracle-sql-helper-ptbr — build.py{Z}")
    log(f"{B}  M&S do Brasil LTDA — contato@msbrasil.inf.br{Z}")
    log(f"{B}{'═'*55}{Z}\n")

    # Descobrir skills
    if args.skill:
        skill_dirs = [SKILLS / args.skill]
        if not skill_dirs[0].exists():
            err(f"Skill não encontrada: {args.skill}")
            sys.exit(1)
    else:
        skill_dirs = sorted(d for d in SKILLS.iterdir() if d.is_dir())

    # ── Modo verificação ──────────────────────────────────────────────────────
    if args.check:
        log("  Verificando consistência...\n")
        total_ok = total_err = 0
        for skill_dir in skill_dirs:
            problemas = verificar(skill_dir)
            if problemas:
                err(skill_dir.name)
                for p in problemas:
                    log(f"    → {p}")
                total_err += 1
            else:
                ok(skill_dir.name)
                total_ok += 1
        sep()
        log(f"  {G}OK: {total_ok}{Z}  |  {R}Erros: {total_err}{Z}\n")
        sys.exit(1 if total_err else 0)

    # ── Modo checksums ────────────────────────────────────────────────────────
    if args.checksums:
        log("  Gerando checksums...\n")
        f = gerar_checksums()
        ok(f"Checksums → {f}")
        return

    # ── Modo build ────────────────────────────────────────────────────────────
    log("  Empacotando skills...\n")
    if BUILD_TMP.exists():
        shutil.rmtree(BUILD_TMP)

    total_ok = total_err = 0
    for skill_dir in skill_dirs:
        log(f"  {C}{skill_dir.name}{Z}")
        skill_file = empacotar_skill(skill_dir)
        if skill_file:
            size_kb = skill_file.stat().st_size / 1024
            ok(f"{skill_file.name} ({size_kb:.1f} KB)")
            total_ok += 1
        else:
            total_err += 1
        log("")

    # Limpar tmp
    if BUILD_TMP.exists():
        shutil.rmtree(BUILD_TMP)

    # Checksums automáticos após build
    sep()
    log("  Gerando checksums...\n")
    gerar_checksums()

    sep()
    log(f"\n{B}  Build concluído:{Z} {G}{total_ok} skills{Z}", )
    if total_err:
        log(f"  {R}{total_err} com erro{Z}")
        sys.exit(1)
    log(f"\n  dist/ pronto para GitHub Release.\n")


if __name__ == "__main__":
    main()
