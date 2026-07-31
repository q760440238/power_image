$ErrorActionPreference = 'Stop'

$outputDirectory = [IO.Path]::GetFullPath(
    (Join-Path $PSScriptRoot '..\assets\benchmark')
)
$stagingDirectory = Join-Path ([IO.Path]::GetTempPath()) (
    'power_image_animals_' + [Guid]::NewGuid().ToString('N')
)

# Animated Noto Emoji by Google, licensed under CC BY 4.0.
# https://googlefonts.github.io/noto-emoji-animation/
# https://creativecommons.org/licenses/by/4.0/
$animals = @(
    @{ Name = 'dog';       Codepoint = '1f415'; Sha256 = '8b2bd2766283df6947ba79c03b1ae0c56ddb680db702b637622bb25a144d2600' },
    @{ Name = 'cow';       Codepoint = '1f42e'; Sha256 = 'd0cd4709a91d7a615f325ffed43a51122e4ff4baeaea5029cb6e69418e59d619' },
    @{ Name = 'unicorn';   Codepoint = '1f984'; Sha256 = '4b719fccb89c8cce8554f43a688fc884af37e3c12790e50af0a96ba84eeeaf6c' },
    @{ Name = 'lizard';    Codepoint = '1f98e'; Sha256 = '13c08b13971d5f1b754dcf9e8876f2863a6dfab81410d5fe45dd5dc19206ed56' },
    @{ Name = 'dragon';    Codepoint = '1f409'; Sha256 = 'ab867fdf3d7fce93a3be43a11ea8060129dfb0d97ccf8a23a9077f484d25f4bb' },
    @{ Name = 'trex';      Codepoint = '1f996'; Sha256 = 'e7a199b0babec6d9ca82f20e2f93c8504ccf5a09718306be52f93ddad83b5a46' },
    @{ Name = 'turtle';    Codepoint = '1f422'; Sha256 = '135eee69a2549622203004894c4b162e66d29a35092e15a5f9f657cc3091ef92' },
    @{ Name = 'crocodile'; Codepoint = '1f40a'; Sha256 = '301e91cc621579b24d5cf39113be54b1a93669848153a411f900eb5da852cd2d' },
    @{ Name = 'snake';     Codepoint = '1f40d'; Sha256 = '3d35540f43331d89f452d623e42c69c4d2ca4f41fde6185d1d2289ec55829a0b' },
    @{ Name = 'frog';      Codepoint = '1f438'; Sha256 = '156e69b0e9cf571119b5f2fcdbe21c67f7d309f8d91882c34b249a721dfe4276' },
    @{ Name = 'rabbit';    Codepoint = '1f407'; Sha256 = '97a573219abb21325c8c1e3c34fea614d2ce3e07c548241df0033ab5fd479db5' },
    @{ Name = 'rat';       Codepoint = '1f400'; Sha256 = '4ca25f96d6d414f1c0d14fa537a97013b3ea77b05d6cd3fe1d82a4733ac69d2b' },
    @{ Name = 'pig';       Codepoint = '1f416'; Sha256 = 'a842a605f42be60174ddda048779b66727320926eda26ce790b1837ff46cceb1' },
    @{ Name = 'horse';     Codepoint = '1f40e'; Sha256 = '1227cf9c78aeda1ce89951cc4138ad92832ee5f5c83d82662fb506326b2d9d03' },
    @{ Name = 'kangaroo';  Codepoint = '1f998'; Sha256 = 'b82b66b9ef80f0f9e8aef448ca9d1bbdd295ef854064d0a8a0e10e6054073819' },
    @{ Name = 'gorilla';   Codepoint = '1f98d'; Sha256 = 'dd22a3d00e1d9eb782c0179016c7f881f7d4f050220f04737dba27ec160d9b4a' },
    @{ Name = 'bird';      Codepoint = '1f426'; Sha256 = 'af7688566fe7f112fdcf09974ce7cf9c864b8182568d1930bbadc8f3628908d7' },
    @{ Name = 'owl';       Codepoint = '1f989'; Sha256 = '358af913f5f247ae1ff82c16e81997b111aa7c588b10d5abd3e8a43ce8a9dcf7' },
    @{ Name = 'dolphin';   Codepoint = '1f42c'; Sha256 = '505c42fb874a25715d1a2f6ec42889c99fed01fb42d2becc6def8deb7a2e859b' },
    @{ Name = 'butterfly'; Codepoint = '1f98b'; Sha256 = '46d58db19d3ec3e3e714307933106064aac4318ced100b173be2d2f9ce8447fa' }
)

New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
New-Item -ItemType Directory -Path $stagingDirectory | Out-Null

try {
    for ($index = 0; $index -lt $animals.Count; $index++) {
        $animal = $animals[$index]
        $fileName = 'animal_{0:D2}_{1}.webp' -f $index, $animal.Name
        $downloadPath = Join-Path $stagingDirectory $fileName
        $sourceUrl = 'https://fonts.gstatic.com/s/e/notoemoji/latest/{0}/512.webp' -f $animal.Codepoint

        Invoke-WebRequest -UseBasicParsing -Uri $sourceUrl -OutFile $downloadPath

        $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $downloadPath).Hash.ToLowerInvariant()
        if ($actualHash -ne $animal.Sha256) {
            throw "SHA-256 mismatch for $fileName. Expected $($animal.Sha256), got $actualHash"
        }
    }

    Get-ChildItem -LiteralPath $outputDirectory -File |
        Where-Object { $_.Name -like 'animated_*.webp' -or $_.Name -like 'animal_*.webp' } |
        Remove-Item -Force

    Copy-Item -Path (Join-Path $stagingDirectory '*.webp') -Destination $outputDirectory
} finally {
    if (Test-Path -LiteralPath $stagingDirectory) {
        Remove-Item -LiteralPath $stagingDirectory -Recurse -Force
    }
}

Write-Output "Downloaded and verified $($animals.Count) distinct animated animal WebP fixtures in $outputDirectory"
