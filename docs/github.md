# How to use ASG with Github Actions?

Assuming your blog is inside the `src` directory inside a GitHub repository,
you just need to create the following file at `.github/workflow/pages.yml` to create
a workflow that will automatically publish and build your blog.

Feel free to update the version provided based on the latest release of ASG.

```yml
name: GitHub Pages

# The blog is published when manually triggered or when you push to the main branch.
on:
  push:
    branches: ["master"]
  pull_request:
    branches: ["master"]
  workflow_dispatch:

permissions:
  id-token: write
  pages: write

jobs:
  build:
    runs-on: ubuntu-latest
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Set up ASG
        run: curl -L https://github.com/vanyle/ASG/releases/download/0.0.5/asg-0.0.5-linux-amd64.tar.gz > asg.tar.gz && tar xzf asg.tar.gz

      - name: Run ASG
        run: ./build/asg src output

      - name: Upload static files as artifact
        uses: actions/upload-pages-artifact@v3
        with:
          path: output/

      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4

```