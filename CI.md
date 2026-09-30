# Continuous integration

`.gitlab-ci.yml` builds the two image variants, pushes them to
`ghcr.io/don-foco/kineticos` (`:default` and `:nvidia`), and — on demand —
builds and publishes the two installer ISOs.

| Stage | Job | Trigger | What it does |
|---|---|---|---|
| image | `image:default` | push to `master`, schedule, web | `dcli-bootc update --no-switch --no-import`, push `:default` |
| image | `image:nvidia`  | push to `master`, schedule, web | `dcli-bootc update --nvidia --no-switch --no-import`, push `:nvidia` |
| iso   | `iso`            | manual | `./build-iso.sh` + `./build-iso.sh nvidia`, upload ISOs |

CI never switches a deployment or edits the overlay manifest — the runner is a
*builder*, not a machine running KineticOS.

---

## 1. You need a builder (self-hosted runner)

GitLab.com's **shared runners cannot do this**. Building a bootc image and an
installer ISO needs rootful/privileged podman, access to
`/var/lib/containers/storage`, and a real filesystem — none of which a shared
container runner gives you. So you register **your own runner** with a shell
executor.

Recommended: a small **Fedora Server VM** (or any spare Fedora machine) with a
few tens of GB of disk. Don't use your daily-driver KineticOS machine as the
builder: builds run `sudo podman` and can leave images and build dirs around,
and it's cleaner to keep the builder disposable.

## 2. Install the runner and build tools

On the builder:

```bash
# GitLab Runner
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo dnf install -y gitlab-runner

# podman + skopeo (dcli-bootc pulls in bootc as a dependency)
sudo dnf install -y podman skopeo
sudo dnf copr enable -y theblackdon/dcli-bootc
sudo dnf install -y dcli-bootc

# sanity check
dcli-bootc --version
podman info >/dev/null && echo "podman OK"
```

## 3. Register the runner

1. In GitLab: your project → **Settings → CI/CD → Runners → New project
   runner**.
2. Give it a tag: **`kineticos-builder`** (the pipeline selects on this tag).
   Leave "Run untagged jobs" off.
3. Copy the authentication token GitLab shows, then on the builder:

```bash
sudo gitlab-runner register \
  --url https://gitlab.com \
  --token <THE_TOKEN> \
  --executor shell
```

Start it and confirm it's online:

```bash
sudo gitlab-runner run     # or: sudo systemctl enable --now gitlab-runner
```

The runner appears green under Settings → CI/CD → Runners with the
`kineticos-builder` tag.

## 4. Let the runner use sudo

The pipeline calls `sudo podman`, `sudo skopeo` and (inside `dcli-bootc`)
`sudo bootc`. On a dedicated builder, grant the runner user passwordless sudo:

```bash
echo 'gitlab-runner ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/gitlab-runner
sudo chmod 0440 /etc/sudoers.d/gitlab-runner
```

> This is root-equivalent access. Only do it on a machine dedicated to
> building.

Also add `gitlab-runner` to `podman` (or make sure `sudo podman` works — it
does regardless). If your `sudo` has `requiretty`, the shell executor can't
use it; remove that for the builder.

## 5. Add the registry secrets

1. Create a GitHub PAT (classic) with the **`write:packages`** scope (add
   `read:packages` too). This is what pushes to `ghcr.io`.
2. In GitLab: your project → **Settings → CI/CD → Variables** → add:
   - `GHCR_USER` = your GitHub username
   - `GHCR_TOKEN` = the PAT, **Masked** and **Protected**

Omit both if the ghcr package is public and you're only pulling.

## 6. Run it

- **Push to `master`** → the two image jobs build and push automatically.
- **Schedule** (Settings → CI/CD → Schedules) → e.g. daily at 03:00, to track
  the moving Bazzite base. Create the schedule once; the image jobs run.
- **Manual ISO** → open a pipeline (CI/CD → Pipelines → *Run pipeline* on
  `master`), let the image jobs finish, then click ▶ on the `iso` job. The ISOs
  are uploaded to the project's Generic Package Registry:

  ```
  https://gitlab.com/api/v4/projects/<PROJECT_ID>/packages/generic/kineticos/<YYYYMMDD>/kineticos-<YYYYMMDD>.iso
  .../kineticos-nvidia-<YYYYMMDD>.iso
  ```

  The job prints the exact URLs. You can turn one into a **Release** link from
  GitLab's Releases page (Deploy → Releases → New release → add a link with the
  package URL).

---

## Building the ISOs manually

`build-iso.sh` wraps bootc-image-builder's `anaconda-iso`; it is exactly what
the `iso` CI job runs. Two ISOs are produced, one per variant. Each ISO's
kickstart points the installed system's update origin at the matching registry
tag, so the variant must be pushed before the ISO is used:

```bash
# AMD / Intel
dcli-bootc build                                    # localhost/kineticos:default
skopeo copy containers-storage:localhost/kineticos:default \
  docker://ghcr.io/don-foco/kineticos:default
./build-iso.sh                                      # output/kineticos-<date>.iso

# NVIDIA
dcli-bootc build --nvidia                           # localhost/kineticos:nvidia
skopeo copy containers-storage:localhost/kineticos:nvidia \
  docker://ghcr.io/don-foco/kineticos:nvidia
./build-iso.sh nvidia                               # output/kineticos-nvidia-<date>.iso
```

The variant selects the kickstart (`disk_config/iso-kineticos.toml` or
`disk_config/iso-kineticos-nvidia.toml`) and the output filename. `build-iso.sh`
pulls `ghcr.io/don-foco/kineticos:<variant>` into rootful podman storage; set
`LOCAL=1` to use an image you built locally instead.

---

## Caveats

- **ISO storage is large.** Each ISO is several GB and GitLab's free tier has a
  namespace storage quota. Old date-versioned packages accumulate — delete
  stale ones (project → Packages and registries) or move ISOs to an
  S3-compatible bucket (Cloudflare R2, Backblaze B2) and have the `iso` job
  upload there instead. Image layers in ghcr are comparatively small.
- **Pull vs push auth.** The ISO job runs `build-iso.sh`, which pulls
  `ghcr.io/don-foco/kineticos:<variant>`. That works only if the package is
  public; if you keep it private, authenticate rootful podman first
  (`echo "$GHCR_TOKEN" | sudo skopeo login ghcr.io -u "$GHCR_USER" --password-stdin`).
- **Disk cleanup.** Builder storage grows. Add a cron or a scheduled job with
  `sudo podman system prune -af` (not while a build runs).
- **`--no-import`.** Image jobs never snapshot the runner's live overlay, so the
  build is reproducible and doesn't modify `modules/overlay-packages.yaml`. Keep
  the builder a plain Fedora host (no `kinpkg`/`rum`), where the overlay sync is
  a no-op anyway.
