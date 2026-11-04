# Thunar (alexhu98 fork)

- Every issue PR adds `explainers/<issue>-<slug>.html`, named after its `<issue>-<slug>` branch and written with the `explainer` skill (`.claude/skills/explainer/`). CI fails the PR without it and renders it into the PR comment. PRs from forks skip that job, so they aren't checked.
