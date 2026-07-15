
# Threat Model

pkgaudit version 0.2.0 is based the following threat model.

## Assets

The assets at risk include data processed in R sessions (e.g., research
datasets, proprietary analyses, clinical trial records, government
statistics, financial models) and the underlying systems on which R
runs. Compromised systems can provide access to credentials such as SSH
keys, cloud provider credentials, and API tokens that enable lateral
movement to downstream systems and services.

## Threats

We focus on threat actors pursuing financial gain through opportunistic
data or credential theft, or system compromise. This is consistent with
documented supply-chain attacks targeting PyPI and npm, which have been
broad and opportunistic, not targeted Zimmermann et al.
([2019](#ref-zimmermann2019small)). The attackers have been
cybercriminals or nation-states behaving like cybercriminals Zanki
([2026](#ref-zanki2026lazarus)). The data may be sold or ransomed, and
systems may be used for botnets, cryptomining, and other purposes. By
contrast, nation-states and commercial competitors may have interest in
data processed in R sessions for purposes of intellectual property theft
or espionage. Hacktivists may seek to disrupt or embarrass government or
commercial entities. However, these actors are likely to use more
targeted attack mechanisms tailored to specific organizations or
high-value targets, rather than broad, opportunistic supply-chain
poisoning.

There may be exceptions. Some R packages are used primarily in specific
industries like pharmaceuticals
([<span class="nocase">pharmaverse</span> 2026](#ref-pharmaverse2026)).
Hypothetically, a targeted attack could seek to compromise one of these
packages or a dependency, but this has not yet been documented.
Nation-state actors also have used supply-chain mechanisms as broad
initial vectors before narrowing their attacks, as in the 2020
SolarWinds Orion compromise in which a trojanized update reached roughly
18,000 customers but follow-on exploitation was limited to a much
smaller subset ([MITRE ATT&CK 2021](#ref-mitre2021solarwinds)). However,
that incident involved compromise of a vendor’s build pipeline rather
than poisoning of a package hosted on an open registry like CRAN, PyPI,
or npm. Accordingly, we scope this threat model to attacks conducted by
financially-motivated threat actors pursuing opportunistic data
exfiltration, credential theft, and system compromise through
supply-chain mechanisms.

## Attack Surface

The attack surface we consider is the `load-time execution` of an R
package and its full dependency graph. When a user installs a package
with `install.packages()`, R resolves and installs every package listed
in that package’s `Depends`, `Imports`, and `LinkingTo` fields,
recursively, typically without further user confirmation ([R Core Team
2026](#ref-rcoreteam2026extensions)). When a package is loaded via
`library()` or `require()` – whether directly by the user or
transitively, as a dependency of another package the user loads – R
automatically executes any code defined in that package’s `.onLoad()`
and `.onAttach()` hooks, before any function exported by the package is
called ([R Core Team 2026](#ref-rcoreteam2026extensions)).

## Scope and Assumptions

We assume the attacker is a malicious maintainer or contributor to an R
package available on CRAN, or capable of impersonating a legitimate
maintainer or contributor for such a package ([Ladisa et al.
2023](#ref-ladisa2023sok)). We do not consider an attacker capable of
compromising CRAN’s infrastructure (e.g., its build pipeline).

## References

<div id="refs" class="references csl-bib-body hanging-indent">

<div id="ref-duan2021measuring" class="csl-entry">

Duan, Ruian, Omar Alrawi, Ranjita Pai Kasturi, Ryan Elder, Brendan
Saltaformaggio, and Wenke Lee. 2021. “Towards Measuring Supply Chain
Attacks on Package Managers for Interpreted Languages.” *28th Annual
Network and Distributed System Security Symposium (NDSS)*.
<https://doi.org/10.14722/ndss.2021.23055>.

</div>

<div id="ref-ladisa2023sok" class="csl-entry">

Ladisa, Piergiorgio, Henrik Plate, Matias Martinez, and Olivier Barais.
2023. “SoK: Taxonomy of Attacks on Open-Source Software Supply Chains.”
*2023 IEEE Symposium on Security and Privacy (SP)*, 1509–26.
<https://doi.org/10.1109/SP46215.2023.10179304>.

</div>

<div id="ref-mitre2021solarwinds" class="csl-entry">

MITRE ATT&CK. 2021. *SolarWinds Compromise, Campaign C0024*.
<a href="https://attack.mitre.org/campaigns/C0024/"
class="uri">Https://attack.mitre.org/campaigns/C0024/</a>.

</div>

<div id="ref-ohm2020backstabber" class="csl-entry">

Ohm, Marc, Henrik Plate, Arnold Sykosch, and Michael Meier. 2020.
“Backstabber’s Knife Collection: A Review of Open Source Software Supply
Chain Attacks.” *Detection of Intrusions and Malware, and Vulnerability
Assessment (DIMVA)*, 23–43.
<https://doi.org/10.1007/978-3-030-52683-2_2>.

</div>

<div id="ref-pharmaverse2026" class="csl-entry">

<span class="nocase">pharmaverse</span>. 2026. *Pharmaverse: A Connected
Network of Companies and Individuals Working to Promote Collaborative
Development of Curated Open Source R Packages for Clinical Reporting
Usage in Pharma*. <a href="https://pharmaverse.org/"
class="uri">Https://pharmaverse.org/</a>.

</div>

<div id="ref-rcoreteam2026extensions" class="csl-entry">

R Core Team. 2026. *Writing R Extensions*. R Foundation for Statistical
Computing.
<https://cran.r-project.org/doc/manuals/r-release/R-exts.html>.

</div>

<div id="ref-zanki2026lazarus" class="csl-entry">

Zanki, Karlo. 2026. *Lazarus Campaign Plants Malicious Packages in Npm
and PyPI Ecosystems*. The Hacker News.
<https://thehackernews.com/2026/02/lazarus-campaign-plants-malicious.html>.

</div>

<div id="ref-zimmermann2019small" class="csl-entry">

Zimmermann, Markus, Cristian-Alexandru Staicu, Cam Tenny, and Michael
Pradel. 2019. “Small World with High Risks: A Study of Security Threats
in the Npm Ecosystem.” *28th USENIX Security Symposium (USENIX Security
19)*, 995–1010. <https://doi.org/10.5555/3361338.3361407>.

</div>

</div>
