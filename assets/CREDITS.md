# 素材の記録

`assets/` に置く素材の出典とライセンス。素材を追加・差し替えたら同じ変更でここに記録する (`make selfcheck` が、`assets/` の全ファイルがこの表に記録されていることを検証する)。

| 素材 | 用途 | 作者・入手元 | ライセンス | 改変 |
|---|---|---|---|---|
| `audio/bgm_day.ogg` | 昼のステージの BGM | 本プロジェクトで自作。`scripts/dev/generate_audio.py` が波形を合成し、ffmpeg (libvorbis) で Ogg Vorbis にエンコードした | 本プロジェクトの一部。外部の素材を含まないため、クレジット表記は不要 | なし |
| `audio/bgm_evening.ogg` | 夕方のステージの BGM | 同上 | 同上 | なし |
| `audio/bgm_night.ogg` | 夜のステージの BGM | 同上 | 同上 | なし |
| `audio/se_attack.wav` | 攻撃の効果音 | 本プロジェクトで自作。`scripts/dev/generate_audio.py` が波形を合成した | 同上 | なし |
| `audio/se_damage.wav` | ダメージの効果音 | 同上 | 同上 | なし |
| `audio/se_sync.wav` | 同期ボーナスの効果音 | 同上 | 同上 | なし |
| `audio/se_stitch.wav` | 影縫いの効果音 | 同上 | 同上 | なし |
