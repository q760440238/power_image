param(
    [string]$Proxy = $env:HTTPS_PROXY
)

$ErrorActionPreference = 'Stop'

$outputDirectory = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\assets\benchmark')
)
$stagingDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'power_image_animals_' + [Guid]::NewGuid().ToString('N')
)

# Noto Color Emoji source images by Google, pinned for reproducibility.
# https://github.com/googlefonts/noto-emoji
$sourceRevision = '8998f5dd683424a73e2314a8c1f1e359c19e8742'
$sourceCacheDirectory = Join-Path $PSScriptRoot (
    "..\.dart_tool\power_image_benchmark_sources\$sourceRevision"
)
$animals = @(
    @{ Name = 'monkey_face';        Codepoint = '1f435' },
    @{ Name = 'monkey';             Codepoint = '1f412' },
    @{ Name = 'gorilla';            Codepoint = '1f98d' },
    @{ Name = 'orangutan';          Codepoint = '1f9a7' },
    @{ Name = 'dog_face';           Codepoint = '1f436' },
    @{ Name = 'dog';                Codepoint = '1f415' },
    @{ Name = 'guide_dog';          Codepoint = '1f9ae' },
    @{ Name = 'service_dog';        Codepoint = '1f415_200d_1f9ba' },
    @{ Name = 'poodle';             Codepoint = '1f429' },
    @{ Name = 'wolf';               Codepoint = '1f43a' },
    @{ Name = 'fox';                Codepoint = '1f98a' },
    @{ Name = 'raccoon';            Codepoint = '1f99d' },
    @{ Name = 'cat_face';           Codepoint = '1f431' },
    @{ Name = 'cat';                Codepoint = '1f408' },
    @{ Name = 'black_cat';          Codepoint = '1f408_200d_2b1b' },
    @{ Name = 'lion';               Codepoint = '1f981' },
    @{ Name = 'tiger_face';         Codepoint = '1f42f' },
    @{ Name = 'tiger';              Codepoint = '1f405' },
    @{ Name = 'leopard';            Codepoint = '1f406' },
    @{ Name = 'horse_face';         Codepoint = '1f434' },
    @{ Name = 'moose';              Codepoint = '1face' },
    @{ Name = 'donkey';             Codepoint = '1facf' },
    @{ Name = 'horse';              Codepoint = '1f40e' },
    @{ Name = 'unicorn';            Codepoint = '1f984' },
    @{ Name = 'zebra';              Codepoint = '1f993' },
    @{ Name = 'deer';               Codepoint = '1f98c' },
    @{ Name = 'bison';              Codepoint = '1f9ac' },
    @{ Name = 'cow_face';           Codepoint = '1f42e' },
    @{ Name = 'ox';                 Codepoint = '1f402' },
    @{ Name = 'water_buffalo';      Codepoint = '1f403' },
    @{ Name = 'cow';                Codepoint = '1f404' },
    @{ Name = 'pig_face';           Codepoint = '1f437' },
    @{ Name = 'pig';                Codepoint = '1f416' },
    @{ Name = 'boar';               Codepoint = '1f417' },
    @{ Name = 'pig_nose';           Codepoint = '1f43d' },
    @{ Name = 'ram';                Codepoint = '1f40f' },
    @{ Name = 'ewe';                Codepoint = '1f411' },
    @{ Name = 'goat';               Codepoint = '1f410' },
    @{ Name = 'camel';              Codepoint = '1f42a' },
    @{ Name = 'two_hump_camel';     Codepoint = '1f42b' },
    @{ Name = 'llama';              Codepoint = '1f999' },
    @{ Name = 'giraffe';            Codepoint = '1f992' },
    @{ Name = 'elephant';           Codepoint = '1f418' },
    @{ Name = 'mammoth';            Codepoint = '1f9a3' },
    @{ Name = 'rhinoceros';         Codepoint = '1f98f' },
    @{ Name = 'hippopotamus';       Codepoint = '1f99b' },
    @{ Name = 'mouse_face';         Codepoint = '1f42d' },
    @{ Name = 'mouse';              Codepoint = '1f401' },
    @{ Name = 'rat';                Codepoint = '1f400' },
    @{ Name = 'hamster';            Codepoint = '1f439' },
    @{ Name = 'rabbit_face';        Codepoint = '1f430' },
    @{ Name = 'rabbit';             Codepoint = '1f407' },
    @{ Name = 'chipmunk';           Codepoint = '1f43f' },
    @{ Name = 'beaver';             Codepoint = '1f9ab' },
    @{ Name = 'hedgehog';           Codepoint = '1f994' },
    @{ Name = 'bat';                Codepoint = '1f987' },
    @{ Name = 'bear';               Codepoint = '1f43b' },
    @{ Name = 'polar_bear';         Codepoint = '1f43b_200d_2744' },
    @{ Name = 'koala';              Codepoint = '1f428' },
    @{ Name = 'panda';              Codepoint = '1f43c' },
    @{ Name = 'sloth';              Codepoint = '1f9a5' },
    @{ Name = 'otter';              Codepoint = '1f9a6' },
    @{ Name = 'skunk';              Codepoint = '1f9a8' },
    @{ Name = 'kangaroo';           Codepoint = '1f998' },
    @{ Name = 'badger';             Codepoint = '1f9a1' },
    @{ Name = 'turkey';             Codepoint = '1f983' },
    @{ Name = 'chicken';            Codepoint = '1f414' },
    @{ Name = 'rooster';            Codepoint = '1f413' },
    @{ Name = 'hatching_chick';     Codepoint = '1f423' },
    @{ Name = 'baby_chick';         Codepoint = '1f424' },
    @{ Name = 'front_facing_chick'; Codepoint = '1f425' },
    @{ Name = 'bird';               Codepoint = '1f426' },
    @{ Name = 'penguin';            Codepoint = '1f427' },
    @{ Name = 'dove';               Codepoint = '1f54a' },
    @{ Name = 'eagle';              Codepoint = '1f985' },
    @{ Name = 'duck';               Codepoint = '1f986' },
    @{ Name = 'goose';              Codepoint = '1fabf' },
    @{ Name = 'owl';                Codepoint = '1f989' },
    @{ Name = 'flamingo';           Codepoint = '1f9a9' },
    @{ Name = 'peacock';            Codepoint = '1f99a' },
    @{ Name = 'parrot';             Codepoint = '1f99c' },
    @{ Name = 'black_bird';         Codepoint = '1f426_200d_2b1b' },
    @{ Name = 'phoenix';            Codepoint = '1f426_200d_1f525' },
    @{ Name = 'frog';               Codepoint = '1f438' },
    @{ Name = 'crocodile';          Codepoint = '1f40a' },
    @{ Name = 'turtle';             Codepoint = '1f422' },
    @{ Name = 'lizard';             Codepoint = '1f98e' },
    @{ Name = 'snake';              Codepoint = '1f40d' },
    @{ Name = 'dragon_face';        Codepoint = '1f432' },
    @{ Name = 'dragon';             Codepoint = '1f409' },
    @{ Name = 'sauropod';           Codepoint = '1f995' },
    @{ Name = 'trex';               Codepoint = '1f996' },
    @{ Name = 'spouting_whale';     Codepoint = '1f433' },
    @{ Name = 'whale';              Codepoint = '1f40b' },
    @{ Name = 'dolphin';            Codepoint = '1f42c' },
    @{ Name = 'seal';               Codepoint = '1f9ad' },
    @{ Name = 'fish';               Codepoint = '1f41f' },
    @{ Name = 'tropical_fish';      Codepoint = '1f420' },
    @{ Name = 'blowfish';           Codepoint = '1f421' },
    @{ Name = 'shark';              Codepoint = '1f988' }
)

if ($animals.Count -ne 100) {
    throw "Expected exactly 100 animals, found $($animals.Count)"
}

$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$staticDirectory = Join-Path $stagingDirectory 'static_webp'
$animatedWebpDirectory = Join-Path $stagingDirectory 'animated_webp'
$gifDirectory = Join-Path $stagingDirectory 'gif'
$directories = @(
    $stagingDirectory,
    $staticDirectory,
    $animatedWebpDirectory,
    $gifDirectory,
    $sourceCacheDirectory
)
foreach ($directory in $directories) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$animationFilter = "format=rgba,scale=420:420:force_original_aspect_ratio=decrease," +
    "pad=512:552:(ow-iw)/2:(oh-ih)/2:color=0x00000000," +
    "crop=512:512:0:20+20*sin(2*PI*n/12)"
$manifest = @()

try {
    for ($index = 0; $index -lt $animals.Count; $index++) {
        $animal = $animals[$index]
        $stem = 'animal_{0:D3}' -f $index
        $sourcePath = Join-Path $sourceCacheDirectory "$stem.png"
        $staticPath = Join-Path $staticDirectory "$stem.webp"
        $animatedWebpPath = Join-Path $animatedWebpDirectory "$stem.webp"
        $gifPath = Join-Path $gifDirectory "$stem.gif"
        $sourceUrl = "https://raw.githubusercontent.com/googlefonts/noto-emoji/" +
            "$sourceRevision/png/512/emoji_u$($animal.Codepoint).png"

        $curlArguments = @(
            '--http1.1', '-L', '--fail', '--silent', '--show-error',
            '--retry', '5', '--retry-all-errors', '--retry-delay', '1'
        )
        if ($Proxy) {
            $curlArguments += @('--proxy', $Proxy)
        }
        $curlArguments += @('--output', $sourcePath, $sourceUrl)
        if (!(Test-Path -LiteralPath $sourcePath) -or
            (Get-Item -LiteralPath $sourcePath).Length -eq 0) {
            & curl.exe @curlArguments
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to download $($animal.Name) from $sourceUrl"
            }
        }

        $staticArguments = @(
            '-y', '-hide_banner', '-loglevel', 'error', '-i', $sourcePath,
            '-c:v', 'libwebp', '-q:v', '80', '-frames:v', '1', $staticPath
        )
        & $ffmpeg @staticArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to encode static WebP for $($animal.Name)"
        }

        $animatedWebpArguments = @(
            '-y', '-hide_banner', '-loglevel', 'error', '-loop', '1',
            '-framerate', '12', '-t', '1', '-i', $sourcePath,
            '-vf', "$animationFilter,format=yuva420p",
            '-c:v', 'libwebp_anim', '-q:v', '80', '-loop', '0', '-an',
            $animatedWebpPath
        )
        & $ffmpeg @animatedWebpArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to encode animated WebP for $($animal.Name)"
        }

        $gifFilter = "$animationFilter,split[a][b];" +
            '[a]palettegen=reserve_transparent=on:stats_mode=diff[p];' +
            '[b][p]paletteuse=alpha_threshold=128'
        $gifArguments = @(
            '-y', '-hide_banner', '-loglevel', 'error', '-loop', '1',
            '-framerate', '12', '-t', '1', '-i', $sourcePath,
            '-filter_complex', $gifFilter, '-loop', '0', $gifPath
        )
        & $ffmpeg @gifArguments
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to encode GIF for $($animal.Name)"
        }

        $manifest += [ordered]@{
            index = $index
            name = $animal.Name
            codepoint = $animal.Codepoint
            source_revision = $sourceRevision
            source_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
            static_webp_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $staticPath).Hash.ToLowerInvariant()
            animated_webp_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $animatedWebpPath).Hash.ToLowerInvariant()
            gif_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $gifPath).Hash.ToLowerInvariant()
        }

        Write-Progress -Activity 'Generating 100 animal fixtures' `
            -Status "$($index + 1)/$($animals.Count) $($animal.Name)" `
            -PercentComplete ((($index + 1) / $animals.Count) * 100)
    }

    $manifest | ConvertTo-Json -Depth 4 | Set-Content `
        -LiteralPath (Join-Path $stagingDirectory 'manifest.json') -Encoding utf8

    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    foreach ($generatedName in @(
        'static_webp', 'animated_webp', 'gif', 'manifest.json'
    )) {
        $generatedPath = Join-Path $outputDirectory $generatedName
        if (Test-Path -LiteralPath $generatedPath) {
            Remove-Item -LiteralPath $generatedPath -Recurse -Force
        }
    }
    Copy-Item -LiteralPath $staticDirectory -Destination $outputDirectory -Recurse
    Copy-Item -LiteralPath $animatedWebpDirectory -Destination $outputDirectory -Recurse
    Copy-Item -LiteralPath $gifDirectory -Destination $outputDirectory -Recurse
    Copy-Item -LiteralPath (Join-Path $stagingDirectory 'manifest.json') `
        -Destination $outputDirectory
} finally {
    Write-Progress -Activity 'Generating 100 animal fixtures' -Completed
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}

Write-Output "Generated 100 unique animals in static WebP, animated WebP and GIF formats."
