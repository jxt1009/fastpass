# Changelog

All notable changes to FastTrack are documented here.

## [0.0.2] - 2026-05-30

### Bug Fixes

- **ci**: Validate release secrets ([`bd1b720`](https://github.com/jtoper/fasttrack/commit/bd1b720b14e2f8382e53d578e94c0c966483de20))
- **ci**: Make itc team id optional ([`9396597`](https://github.com/jtoper/fasttrack/commit/9396597c61e9cd9a4f52417daf2a6fb51d745c3c))

## [0.0.1] - 2026-05-30

### Bug Fixes

- Prevent Core Location crash in simulator ([`11d9f4a`](https://github.com/jtoper/fasttrack/commit/11d9f4a567e46fe85ada20b475a1192806c25da9))
- **ci**: Add configurable SSH port for deployment ([`4ba2775`](https://github.com/jtoper/fasttrack/commit/4ba2775ddfbb2ca6f6110651fbc51ba168a74c4c))
- **ci**: Scope deploy job to production environment ([`86c066d`](https://github.com/jtoper/fasttrack/commit/86c066d94e505caec7d470fe36441451796c8a35))
- **ci**: Grant packages:write permission for GHCR push ([`512e8e8`](https://github.com/jtoper/fasttrack/commit/512e8e85e090de32fc46cb3658676d9b739ebd17))
- **ci**: Use macos-15 for Xcode 16 and improve k8s connectivity error message ([`a107379`](https://github.com/jtoper/fasttrack/commit/a10737912f3e270bdad4c5c9bbf339087dccc1d5))
- **ci**: Skip TLS cert verification for public IP k8s access ([`61afbd6`](https://github.com/jtoper/fasttrack/commit/61afbd6ad518cebe954369f6f32a34680ce1bc0e))
- **k8s**: Restore includeSelectors/includeTemplates to match deployed state ([`22f826d`](https://github.com/jtoper/fasttrack/commit/22f826d76ff0247d2590a90a641f9d2a3ffa10f4))
- **ios**: Timer lag, speed-at-stop, and 16G deceleration spike ([`3162fc4`](https://github.com/jtoper/fasttrack/commit/3162fc4ae86155adf479e620c7614327913de98c))
- Use dynamic cluster name for insecure-skip-tls-verify in CI/CD ([`f021d13`](https://github.com/jtoper/fasttrack/commit/f021d130910acac5ba53898b4dbbb92713ceae42))
- Move images block to overlays so CI kustomize edit set image works correctly ([`1d6fa0e`](https://github.com/jtoper/fasttrack/commit/1d6fa0e6aa6e18aca2ed7cce27ce12cadbc4785b))
- Add ghcr imagePullSecret and increase rollout timeout ([`fd8de76`](https://github.com/jtoper/fasttrack/commit/fd8de7611ac54dffe47d720e4b8d3ac61a4f9c7e))
- Include google-client-id/secret in CI secret creation ([`72911af`](https://github.com/jtoper/fasttrack/commit/72911af41bf11097e5dc5be4eb5ea295f99d7fcc))
- Resolve avatar upload 413 error ([`62e6695`](https://github.com/jtoper/fasttrack/commit/62e6695d593aa230b40ad7a548d275550be6870c))
- Persist uploads across deploys, separate staging/prod DB and secrets ([`73f323f`](https://github.com/jtoper/fasttrack/commit/73f323f2077ced80ff68e96fd288aedba8242e8a))
- App Store compliance - Keychain tokens, legal links, safety disclaimer ([`aaadd9c`](https://github.com/jtoper/fasttrack/commit/aaadd9c2973392b72f1a0e1c46ba530dd090914c))
- Use merge-patch for k8s secrets to prevent key clobbering on deploy ([`38a30ed`](https://github.com/jtoper/fasttrack/commit/38a30edd6e516e2d5b21b54226233859db0de0fa))
- Deploy no longer fails when required secrets already exist on cluster ([`3f1155d`](https://github.com/jtoper/fasttrack/commit/3f1155db09f66a11188aa19f642743b9d00a2136))
- Live timer freeze and broken playback controls ([`7b15538`](https://github.com/jtoper/fasttrack/commit/7b15538ab8a78daa9c653002579facb06bbdbf8a))
- Remove invalid [weak self] capture in struct Timer closure ([`bbca5ba`](https://github.com/jtoper/fasttrack/commit/bbca5ba6ee03248f45542d7d6097989a31bf27ef))
- Analytics view stuck loading forever ([`dc20a9a`](https://github.com/jtoper/fasttrack/commit/dc20a9a83143a650e0094efd802ee034afc68ba2))
- Leaderboard 0-60, filter rebuild, analytics first-load ([`35968bb`](https://github.com/jtoper/fasttrack/commit/35968bbc0146640906594bf70a8d65a46bc48bb8))

### CI/CD

- Add release pipeline, tests, App Store compliance, and conventional commits ([`aefd209`](https://github.com/jtoper/fasttrack/commit/aefd209181129e80642883e3b03a760ad773abf5))
- Re-trigger deploy after RBAC fix ([`96955a6`](https://github.com/jtoper/fasttrack/commit/96955a621b54d9c0358e98d4c1d44992784ba3c3))
- Touch workflow to re-trigger after RBAC fix ([`10f9964`](https://github.com/jtoper/fasttrack/commit/10f9964d6a57e75744f84b55a860950e7fe0f1a7))
- Re-trigger deploy after RBAC fix for PV/PVC permissions ([`9f2c4b4`](https://github.com/jtoper/fasttrack/commit/9f2c4b4f6e058dff73ebc5a28dccb415f3753324))
- Trigger deploy after RBAC PV/PVC permission fixes ([`f3ecf41`](https://github.com/jtoper/fasttrack/commit/f3ecf4123bb4994b125f4e101444d8fd980ae49c))

### Documentation

- Add comprehensive features documentation ([`94fb37b`](https://github.com/jtoper/fasttrack/commit/94fb37b9e101768c225f2d2fdee4e9f3642744ae))
- Add quick deployment reference guide ([`80126ff`](https://github.com/jtoper/fasttrack/commit/80126ff742696c13e3dc83f0dc8b685ebc0b9027))
- Add comprehensive deployment summary ([`4fdd0e2`](https://github.com/jtoper/fasttrack/commit/4fdd0e2d717108264d4c1019c818b74662339f1e))
- Update README with comprehensive guide ([`9e91e3e`](https://github.com/jtoper/fasttrack/commit/9e91e3eb0b51a0c2275f06103c12335e9f4bdad5))
- Expand GitHub secrets guide with generation commands and Apple approval status ([`d3f8d83`](https://github.com/jtoper/fasttrack/commit/d3f8d83499fd341b1b536e2b0471ba22662d9d90))

### Feature

- Add live map tracking and enhanced drive statistics ([`2964b0b`](https://github.com/jtoper/fasttrack/commit/2964b0bc4d292223ac800a43569104e370152b3b))

### Features

- Configure deployment for fast.toper.dev ([`fddb192`](https://github.com/jtoper/fasttrack/commit/fddb192a1bcafde17fe1b8b1b5e2e4317a464efd))
- Independent PostgreSQL with automated backups ([`3adebe4`](https://github.com/jtoper/fasttrack/commit/3adebe48e7085ec2eb4d92bbf294ce8aa9d5bf89))
- **observability**: Add Prometheus, Grafana, Loki, Alertmanager stack ([`f5e001e`](https://github.com/jtoper/fasttrack/commit/f5e001eda03fd227bf1db4741b28be5207ccd65f))
- **infra**: Add Kustomize multi-environment k8s overlays ([`2539231`](https://github.com/jtoper/fasttrack/commit/2539231386ea689c35ab4ed69d6bc5dd7e758401))
- **infra**: Deploy staging and production to server ([`d95fe84`](https://github.com/jtoper/fasttrack/commit/d95fe84538ac19004f8ce701a5e09b3dbbf2f90b))
- **k8s**: Add GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET env vars to deployment ([`0c6d4d0`](https://github.com/jtoper/fasttrack/commit/0c6d4d05a356e92ffb01d6813b1e25a5e3be073e))
- Leaderboard avatars, analytics real data, drive playback + event markers ([`93f6954`](https://github.com/jtoper/fasttrack/commit/93f6954cf988935ce00d5601a0614de579f3b02c))
- Add shimmer skeleton loading states throughout app ([`33b4404`](https://github.com/jtoper/fasttrack/commit/33b4404d83bc6aec4279b34d7a12d995e6184f81))
- FastTrack marketing website with privacy policy and terms ([`c1576eb`](https://github.com/jtoper/fasttrack/commit/c1576eb06817ee38746757a60af21ad9a4e4a3f8))
- Expandable full-screen map in DriveDetailView ([`ceb8a86`](https://github.com/jtoper/fasttrack/commit/ceb8a8614ca7d01954a8cd6d597b88f6fb7c24ee))
- Smooth playback interpolation in DriveDetailView ([`ec519a2`](https://github.com/jtoper/fasttrack/commit/ec519a21e930f4c3bda9e52ee70b046b5e36aaf7))
- Consolidate More tab into unified Profile tab ([`46e2c1e`](https://github.com/jtoper/fasttrack/commit/46e2c1e800cca2eac3d8ab43af603c0bf4308457))

### Fix

- SwiftUI compilation errors ([`d94d46b`](https://github.com/jtoper/fasttrack/commit/d94d46baa91b91ce3b9157686a9ed4d32a029a92))
- Core Location crashes in Xcode previews ([`fee2508`](https://github.com/jtoper/fasttrack/commit/fee2508addd7bcc2861ea33cd71ac15888773aba))


