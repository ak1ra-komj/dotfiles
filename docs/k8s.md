
## `stow k8s`

`k8s-kubeconfig-selector.sh` 为一个通过菜单设置 `KUBECONFIG` 环境变量的小工具; `~/.kube` 下的 KUBECONFIG 文件以 `.conf` 结尾, `~/.bash_alias` 中已经预先添加了 `kc` alias, 使用时只需输入 `kc`, 然后输入集群菜单前的数字序号即可.

> 小提醒, 在新增 AWS 管理的 EKS 时, 可以先 touch 一个空文件, 用 `kc` 选择它, 然后再执行 `aws eks update-kubeconfig`, 这样可以避免 `aws` 命令将所有文件都写到当前的 `KUBECONFIG` 环境变量所指的文件或者 `~/.kube/config` 文件中. 设计之初 KUBECONFIG 是可以包含多个集群信息, 可是我觉得不好用, 因此还是决定分文件存放不同集群信息.

`kube-dump.sh` 用于批量导出 Kubernetes 中所有资源的 manifest, 过程中使用 `jq` 删除一些再次导入别的集群时不再需要的字段或者由 Rancher 添加的自定义字段.

`kube-convert.sh` 是 [kubectl convert plugin](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-convert-plugin) 的封装, 用于批量对当前目录下的所有 manifest 执行 kubectl convert, 该插件没有提供 in-place 修改选项, 因此使用了临时文件, 执行时短时间内会有大量小文件读写, 可能存在性能问题.
