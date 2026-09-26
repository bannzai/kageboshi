# Kageboshi の検証・ビルド入口。target 命名は ~/.claude/rules/makefile-target-naming.md に従う
# (`build-<対象>` = エクスポートだけ。`run` = エディタなしでの起動)。
#
# GODOT は Godot 4.7 の実行ファイル。macOS ローカルの既定値は /Applications/Godot.app。CI では
# 環境変数 GODOT で Linux バイナリを渡す。
GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
LOG_DIR := tmp
# Godot 自身のログの出力先。指定しないと user:// に書こうとし、書き込みを拒否するサンドボックスでは
# 起動に失敗するため、すべての Godot 起動に付ける ($@ は実行中の target 名)
ENGINE_LOG = --log-file $(abspath $(LOG_DIR))/$@.godot.log

# 描画付きで起動する target (screenshot / movie) の共通オプション。headless では描画されないため付けない。
# CI の Linux では Xvfb + Mesa llvmpipe 上で実行する
WINDOWED_FLAGS := --audio-driver Dummy --rendering-driver opengl3 --resolution 1280x720 --windowed --position 0,0
# 描画付き起動でだけ出る、描画に影響しない OS / ドライバ由来の行。ログの WARNING / ERROR 検査から除外する
# (llvmpipe は V-Sync を設定できない WARNING を毎回 1 件出す。macOS は入力メソッドの mach port のエラーを稀に出す)
WINDOWED_LOG_NOISE := -e 'Could not set V-Sync mode' -e 'IMKCFRunLoopWakeUpReliable'
# movie target が録画するフレーム数 (30 fps 固定。150 = 5 秒)。操作なしの起動〜メインシーン表示の確認には
# 数秒あれば足り、CI の録画時間と artifact のサイズを抑えるため
MOVIE_FRAMES ?= 150

.PHONY: import check selfcheck integration lint test screenshot movie run build-macos build-windows build-linux build-all clean

# ログ・撮影の出力先。.gdignore を置き、撮影した PNG を Godot に import させない
$(LOG_DIR)/.gdignore:
	@mkdir -p $(LOG_DIR)
	@touch $@

# アセットのインポート (初回・素材追加後)。.godot/ を生成する
import: $(LOG_DIR)/.gdignore
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --import > $(LOG_DIR)/import.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/import.log; \
	tail -n 1 $(LOG_DIR)/import.log | grep -q '^exit=0$$'

# 起動検証。メインシーンとスクリプトがロードでき、_ready が走ることを boot 出力で確認する
check: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --quit > $(LOG_DIR)/check.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/check.log; \
	grep -q '^kageboshi boot$$' $(LOG_DIR)/check.log
	tail -n 1 $(LOG_DIR)/check.log | grep -q '^exit=0$$'
	! grep -i -e 'WARNING' -e 'ERROR' $(LOG_DIR)/check.log

# 移動・スクロール・攻撃・敵・体力・同期ボーナス・光源による影の反転と倍率の計算、入力割り当て、シーンのロードの検証 (headless)
selfcheck: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --script res://scripts/dev/selfcheck.gd > $(LOG_DIR)/selfcheck.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/selfcheck.log; \
	grep -q '^selfcheck OK$$' $(LOG_DIR)/selfcheck.log
	tail -n 1 $(LOG_DIR)/selfcheck.log | grep -q '^exit=0$$'
	! grep -i -e 'WARNING' -e 'ERROR' $(LOG_DIR)/selfcheck.log

# キー入力でメインシーンを動かす入力統合テスト (headless)。主人公の移動・ジャンプ・地形との当たり判定・
# スクロールと影の同期、攻撃・被弾・ゲームオーバー・同期ボーナス、光源をまたいだ反転区間での影の反転と伸び縮みを確認する
integration: import
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --script res://scripts/dev/integration.gd > $(LOG_DIR)/integration.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/integration.log; \
	grep -q '^integration OK$$' $(LOG_DIR)/integration.log
	tail -n 1 $(LOG_DIR)/integration.log | grep -q '^exit=0$$'
	! grep -i -e 'WARNING' -e 'ERROR' $(LOG_DIR)/integration.log

# GDScript の lint (gdtoolkit の gdlint。設定は ./gdlintrc)
lint:
	gdlint scripts/

# headless 検証の一括実行 (CI の lint / check-and-export job と同じ内容。描画付きの screenshot / movie は含まない)
test: lint check selfcheck integration

# 実際の描画で代表画面を撮影する (headless の検証では見た目の崩れを検出できない)。撮影した PNG は目視してから
# 完了報告する
screenshot: import
	rm -f $(LOG_DIR)/screenshot-*.png
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --script res://scripts/dev/screenshot.gd > $(LOG_DIR)/screenshot.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/screenshot.log; \
	tail -n 1 $(LOG_DIR)/screenshot.log | grep -q '^exit=0$$'
	! grep -i -e 'WARNING' -e 'ERROR' $(LOG_DIR)/screenshot.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ls $(LOG_DIR)/screenshot-*.png

# 操作を伴わない起動〜メインシーン表示を Movie Maker モードで録画して mp4 にする (起動直後の描画崩れ・真っ黒を
# 検出する。headless は dummy レンダラで落ちるため描画付きで起動する)。真っ黒な動画を成功と誤認しないよう、
# 終了 1 秒前のフレームの輝度平均 (Y。limited range のため真っ黒 = 16) が 32 以上であることも検査する
movie: import
	rm -f $(LOG_DIR)/movie.avi $(LOG_DIR)/movie.mp4
	"$(GODOT)" $(ENGINE_LOG) --path . $(WINDOWED_FLAGS) --write-movie $(LOG_DIR)/movie.avi --fixed-fps 30 --quit-after $(MOVIE_FRAMES) > $(LOG_DIR)/movie.log 2>&1; \
	echo "exit=$$?" >> $(LOG_DIR)/movie.log; \
	tail -n 1 $(LOG_DIR)/movie.log | grep -q '^exit=0$$'
	! grep -i -e 'WARNING' -e 'ERROR' $(LOG_DIR)/movie.log | grep -v $(WINDOWED_LOG_NOISE) | grep -q .
	ffmpeg -loglevel error -y -i $(LOG_DIR)/movie.avi -c:v libx264 -pix_fmt yuv420p $(LOG_DIR)/movie.mp4
	rm -f $(LOG_DIR)/movie.avi
	ffmpeg -v error -sseof -1 -i $(LOG_DIR)/movie.mp4 -frames:v 1 -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=- -f null - \
	  | awk -F= '/YAVG/ { found = 1; exit ($$2 >= 32) ? 0 : 1 } END { if (!found) exit 1 }'

# エディタなしでゲームを起動する (手動確認用)
run: $(LOG_DIR)/.gdignore
	"$(GODOT)" $(ENGINE_LOG) --path .

# デスクトップ向けエクスポート。プリセット名は export_presets.cfg と一致させる。
# 実行には Godot 4.7 の export templates が必要 (AGENTS.md「検証方法」参照)
build-macos: import
	@mkdir -p build/macos
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "macOS" build/macos/kageboshi.zip
	test -f build/macos/kageboshi.zip

build-windows: import
	@mkdir -p build/windows
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Windows Desktop" build/windows/kageboshi.exe
	test -f build/windows/kageboshi.exe
	test -f build/windows/kageboshi.pck

build-linux: import
	@mkdir -p build/linux
	"$(GODOT)" --headless $(ENGINE_LOG) --path . --export-release "Linux" build/linux/kageboshi.x86_64
	test -f build/linux/kageboshi.x86_64
	test -f build/linux/kageboshi.pck

build-all: build-macos build-windows build-linux

clean:
	rm -rf build $(LOG_DIR)
