# BlenderLore Harbor 评估

本项目用于通过 Harbor 启动 Codex 或 Claude Code，让 agent 完成 BlenderLore 任务，并使用独立的 GPT-5.5 Judge 对结果进行评分。

评估分为两类：

- 静态任务：从 agent submission 中收集六视图渲染图，交给多模态 Judge 按 `rubric.json` 评分。
- 动态任务：读取 agent submission 中的 MP4，使用 FFprobe 获取视频信息、FFmpeg 抽帧，再交给 Judge 按动态 rubric 评分。

## 目录结构

```text
blenderlore/
├── data/                         # BlenderLore 任务定义
│   └── <task>/output/
│       ├── task.md               # 提供给 Codex/Claude Code 的任务说明
│       └── rubric.json           # Judge 使用的评分标准
├── eval/                         # 评估器 Python 包
├── scripts/
│   ├── install_blender_runtime.sh
│   ├── run_harbor.sh
│   ├── run_all_tasks.sh
│   ├── run_codex.sh
│   ├── run_codex_sol.sh
│   ├── run_codex_astra.sh
│   ├── run_claude_fable.sh
│   └── run_kimi_code.sh
├── configs/
│   └── agents.yaml              # 四组 Harbor agent 配置
├── judge.yaml                    # 本地 Judge 配置，不应提交到公开仓库
└── pyproject.toml
```

## 1. 安装 Python 与 Harbor

建议在独立虚拟环境中安装：

```bash
cd /Users/rswang/Desktop/blenderlore
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -e '.[judge]'
```

Harbor 本身需要按照你们实际使用的 Harbor 发行版安装。安装后确认：

```bash
harbor --help
```

如果 Harbor 由系统或容器提供，则只需确保 `harbor` 命令在 `PATH` 中。

## 2. 安装 Blender 运行环境

安装脚本面向 Harbor 常用的 Debian/Ubuntu Linux x86_64 环境：

```bash
sudo ./scripts/install_blender_runtime.sh
source /opt/blender/blenderlore-env.sh
```

脚本会安装并验证：

- Blender 5.1.2
- Blender Python（随 Blender 分发）
- EEVEE（Blender 内置）
- Cycles（Blender 内置）
- FFmpeg
- FFprobe

如需安装到其他目录：

```bash
sudo ./scripts/install_blender_runtime.sh --prefix /opt/blender
```

如果 FFmpeg 已经由基础镜像安装，可以跳过 apt：

```bash
sudo ./scripts/install_blender_runtime.sh --skip-apt
```

启动脚本会自动加载 `/opt/blender/blenderlore-env.sh`。也可以手动设置：

```bash
export BLENDERLORE_BLENDER_BIN=/opt/blender/current/blender
export BLENDERLORE_FFMPEG_BIN=/usr/bin/ffmpeg
export BLENDERLORE_FFPROBE_BIN=/usr/bin/ffprobe
```

## 3. 配置 Judge

Judge 使用独立的 GPT-5.5 配置，存放在项目根目录的 `judge.yaml`：

```yaml
judge:
  provider: openai
  model: gpt-5.5
  base_url: https://console.cloudrouter.online
  api_key: <judge-api-key>
```

该文件已加入 `.gitignore`。也可以通过环境变量覆盖：

```bash
export BLENDERLORE_JUDGE_CONFIG=/path/to/judge.yaml
export BLENDERLORE_EVAL_JUDGE_MODEL=gpt-5.5
```

Judge 与 Harbor agent 使用独立的 API、Key 和 Base URL，不会互相复用。

离线检查评估流程时，可以使用 stub：

```bash
export BLENDERLORE_EVAL_JUDGE=stub
```

stub 不进行真实视觉判断，所有 criterion 得分为 0，仅用于检查文件流转和结果输出。

## 4. 准备 Harbor 任务

每个 Harbor task 应至少提供以下内容：

```text
<harbor-task>/
├── task.toml 或 Harbor 任务配置
├── tests/
│   └── test.sh                 # 调用 eval/harbor_test.sh
└── task/                       # 挂载为 /tests/task
    └── output/
        ├── task.md
        └── rubric.json
```

agent 的工作目录应挂载为 `/workspace/submission`。任务 verifier 中可以直接调用：

```bash
export PYTHONPATH=/path/to/blenderlore:$PYTHONPATH
export BLENDERLORE_TASK_DIR=/tests/task
export BLENDERLORE_SUBMISSION_DIR=/workspace/submission
/path/to/blenderlore/eval/harbor_test.sh
```

`harbor_test.sh` 会将结果写入：

```text
/logs/verifier/reward.txt
/logs/verifier/breakdown.json
```

Harbor 读取 `reward.txt` 作为该 trial 的最终 reward。

## 5. 通过 Codex 启动

先配置 Harbor agent 使用的凭证：

```bash
export OPENAI_API_KEY=<agent-api-key>
```

然后启动：

```bash
./scripts/run_codex.sh \
  -p <harbor-task-path> \
  --ak reasoning_effort=medium
```

如果 Harbor 使用其他 OpenAI-compatible 网关：

```bash
export OPENAI_BASE_URL=https://your-agent-gateway.example.com
export OPENAI_API_KEY=<agent-api-key>
./scripts/run_codex.sh -p <harbor-task-path>
```

agent 模型默认是 `gpt-5.5`，可覆盖：

```bash
export BLENDERLORE_AGENT_MODEL=gpt-5.5
```

## 6. 通过 Claude Code 启动

配置 Harbor agent 使用的 Anthropic 凭证：

```bash
export ANTHROPIC_AUTH_TOKEN=<agent-token>
export ANTHROPIC_BASE_URL=https://api.anthropic.com
```

启动：

```bash
./scripts/run_claude_code.sh \
  -p <harbor-task-path>
```

可覆盖 agent 模型：

```bash
export BLENDERLORE_AGENT_MODEL=claude-sonnet-4-5
```

Claude Code/Codex 的凭证只注入 Harbor agent 子进程；Judge 仍读取 `judge.yaml`。

## 6.1 四个固定模型配置

四组 agent 配置记录在本地 `configs/agents.yaml`，对应的启动脚本如下：

```bash
./scripts/run_codex_sol.sh -p <harbor-task-path>
./scripts/run_codex_astra.sh -p <harbor-task-path>
./scripts/run_claude_fable.sh -p <harbor-task-path>
./scripts/run_kimi_code.sh -p <harbor-task-path>
```

## 2026-09-16 五任务运行结果

| 任务 | 类型 | 最终分 | 生成 tokens | Codex 回复块 | 执行命令数 | 生成耗时估计 | 生成结束 UTC | 最终评测耗时 | render | judge |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| B01 骨骼控制的贝塞尔软管 | static | 0.200 | 87,203 | 19 | 25 | ~9m26s | 08:00:45 | 26.692s | 8.676s | 18.016s |
| B02 金属球水体波纹 | dynamic | 0.850 | 97,493 | 15 | 36 | ~12m17s | 08:13:02 | 30.868s | 0.652s | 30.215s |
| B03 玻璃蜂蜜罐 | dynamic | 0.725 | 104,492 | 22 | 26 | ~19m25s | 08:32:27 | 41.354s | 0.541s | 40.812s |
| B04 可伸缩弹簧系统 | dynamic | 0.625 | 106,091 | 19 | 29 | ~17m17s | 08:49:44 | 75.574s | 0.711s | 74.863s |
| B05 开放式线粒体 | static | 0.800 | 43,130 | 8 | 7 | ~5m08s | 08:54:52 | 90.567s | 55.571s | 34.995s |

分别对应 `gpt-5.6-sol`、`gpt-6-astra`、`claude-fable-5-1` 和 `kimi-k3`。
其中 Kimi K3 使用 Codex/OpenAI Responses 通道，因为该 Key 被标注为只能用于 Codex；Claude Fable 使用 Claude Code/Anthropic 通道。

## 6.2 完整运行全部任务

当前 `data/` 中共有 **147 个任务**：

- 静态任务：126 个
- 动态任务：21 个

每个模型都可以通过全量脚本运行全部任务。脚本按稳定排序逐个提交 Harbor，单个任务失败后会继续运行剩余任务：

```bash
./scripts/run_all_tasks.sh codex-sol
./scripts/run_all_tasks.sh codex-astra
./scripts/run_all_tasks.sh claude-fable
./scripts/run_all_tasks.sh kimi-code
```

也可以指定自定义任务目录：

```bash
BLENDERLORE_DATA_DIR=/path/to/tasks ./scripts/run_all_tasks.sh codex-sol
```

任务数量由运行时扫描目录得到，不依赖手工维护的数字；启动时会打印总任务数和每个任务的进度，结束时打印失败数量。

默认模式是完整运行全部任务。单独传入 `--test` 才会切换为测试模式，只运行稳定排序后的前 5 个任务；测试模式的输出文件、进度格式、manifest 字段和评估流程与完整模式相同，只有任务数量不同：

```bash
./scripts/run_all_tasks.sh codex-sol --test
```

也可以通过环境变量开启测试模式：

```bash
BLENDERLORE_TEST=1 ./scripts/run_all_tasks.sh codex-sol
```

不传 `--test` 且未设置 `BLENDERLORE_TEST=1` 时，始终运行完整任务集。

默认每个任务完成生成后会自动运行 Judge。Direct 模式下评估结果写入同一 run 目录的任务子目录：

```text
<jobs>/<run_id>/<index>/evaluation/reward.txt
<jobs>/<run_id>/<index>/evaluation/breakdown.json
<jobs>/<run_id>/<index>/judge.log
```

如只想生成、不评分，可以关闭自动 Judge：

```bash
BLENDERLORE_AUTO_JUDGE=0 ./scripts/run_all_tasks.sh codex-sol --test
```

可以用 `BLENDERLORE_PARALLEL` 并发执行任务；默认值为 `1`，即串行：

```bash
BLENDERLORE_DIRECT=1 BLENDERLORE_PARALLEL=2 ./scripts/run_all_tasks.sh codex-sol --test
```

全量运行还会在 jobs 目录生成 JSONL manifest，记录 run id、模型 profile、任务总数、每个任务生成状态、Judge 状态、reward、失败数和时间戳。

## 6.3 执行指标

每个任务的 `breakdown.json` 除 rubric 得分外还记录：

- completion、build、render、deliverable 状态
- GEO/SURF/PIPE 等 capability 分项得分
- 静态任务六视图完整率
- 动态任务视频抽帧数量和 FFprobe 元数据
- 端到端、证据处理、Judge 评估耗时
- agent steps/turns/tool calls、重试次数（由 Harbor 日志提供时写入）
- agent/Judge token、API 请求和失败统计（由 Harbor/provider 日志提供时写入）
- failure_type 失败分类

无法从当前 verifier 进程可靠获得的 agent/token 字段会保留为 `null`，不会伪造统计值。

## 7. 直接运行评估器

不经过 Harbor 时，可以直接评估一个已有 submission：

```bash
python -m eval \
  --task data/B36_玻璃猫爪挂件 \
  --submission /path/to/submission \
  --output /tmp/blenderlore-eval
```

动态任务示例：

```bash
python -m eval \
  --task data/B53_Luminous_Star_Rain_dynamic \
  --submission /path/to/submission \
  --output /tmp/blenderlore-eval
```

## 8. Submission 文件约定

静态任务的 submission 至少应包含六张最终渲染图。文件名最好包含以下视图名：

```text
front.png
back.png
left.png
right.png
top.png
bottom.png
```

如果文件名没有视图名，评估器会按稳定排序选择前六张图像。

动态任务至少应包含一个 MP4：

```text
submission.blend
build.py
B53_Luminous_Star_Rain_dynamic.mp4
```

评估器会抽取视频帧，并将视频元数据写入结果文件。Blender 工程、`build.py`、PNG/MP4 是否满足 rubric 中的交付要求，由 Judge 根据任务 rubric 判断。

## 9. 结果文件

评估输出目录包含：

```text
reward.txt       # Harbor 读取的 0..1 reward
breakdown.json   # 任务类型、环境、证据、criterion 分数和错误
frames/          # 动态 MP4 的抽帧结果
```

最终 reward 的计算方式为：

```text
sum(criterion_points * normalized_score) / total_points
```

其中 `PASS=1.0`、`PARTIAL=0.5`、`FAIL=0.0`。

## 10. 常见问题

### 找不到 Blender 或 FFmpeg

检查：

```bash
command -v blender
command -v ffmpeg
command -v ffprobe
```

或者显式设置 `BLENDERLORE_BLENDER_BIN`、`BLENDERLORE_FFMPEG_BIN` 和 `BLENDERLORE_FFPROBE_BIN`。

### Judge 报 API Key 缺失

确认 `judge.yaml` 存在且格式正确，或者设置：

```bash
export BLENDERLORE_JUDGE_API_KEY=<key>
export BLENDERLORE_JUDGE_BASE_URL=https://console.cloudrouter.online
```

### 动态任务没有抽到帧

确认 submission 中存在可播放的 `.mp4`，并检查：

```bash
ffprobe <submission.mp4>
```

### Harbor 找不到评估器

确保 Harbor verifier 进程的 `PYTHONPATH` 包含项目根目录：

```bash
export PYTHONPATH=/path/to/blenderlore:$PYTHONPATH
```
