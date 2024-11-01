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
    branches: ["main"]
  workflow_dispatch:

permissions:
  id-token: write
  pages: write

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - name: Set up ASG
        run: curl -L https://github.com/vanyle/ASG/releases/download/0.0.1/asg-0.0.1-linux-amd64.tar.gz > asg.tar.gz && tar xzf asg.tar.gz

      - name: Run ASG
        run: ./build/asg src output

      - name: Upload static files as artifact
        id: deployment
        uses: actions/upload-pages-artifact@v3
        with:
          path: output/

  deploy:
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}
    runs-on: ubuntu-latest
    needs: build
    steps:
      - name: Deploy to GitHub Pages
        id: deployment
        uses: actions/deploy-pages@v4
```