# render with: https://www.websequencediagrams.com/
title The Big Picture

API Auth ->+API Scarp: API\ntokens
destroy API Auth

API Scarp -> API Scarp: scarp API
API Scarp -> API Scarp: save posts to *.json cache

API Scarp ->+Normalize:
destroy API Scarp

Normalize -> Normalize: load posts from *.json cache
Normalize -> Normalize: determine best URL
Normalize -> Normalize: normalize XMP tags
Normalize -> Normalize: cache normalized data to *.yaml

Normalize -->+Download:
Destroy Normalize

Download -> Download: load data from *.yaml
Download -> Download: download + tag images
