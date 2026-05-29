# PM（枢） — 用户偏好记忆

> 最后更新: 2026-05-25

## 沟通偏好

- 用户偏好中文沟通，代码注释用英文
- 用户喜欢直接、结构化的分析输出（表格、流程图、优先级排序）
- 用户使用维弈阁多角色 AI 团队协作模式

## 工作习惯

- 项目使用 .weiyige/ 目录管理 AI 角色和协作流程
- 文档组织在 docs/ 下，按 knowledge/requirements/design/architecture/product 分类
- 需求拆分为独立 REQ-X.Y-ZZ.md 文件，每个有验收标准
- 使用 ai-workspace/ 管理任务队列和项目状态

## 技术偏好

- macOS 原生开发（AppKit + Swift）
- 使用 XcodeGen (project.yml) 管理项目配置
- 测试框架: swift-snapshot-testing + XCUITest
- 构建脚本: build-app.sh（命令行构建，非 Xcode GUI）
- SDK 与 App 分离架构（AudioRecordKit 为独立 Swift Package）
