---
date: 2024-10-24
categories:
  - Go
draft: false
---

# Go 笔记

![](../assert/go.png)
/// caption
///

<!-- more -->
## 基础

**make 语法**
```go
// 初始 cap 为 10，len 为 0
slice = make([]int, 0, 10)

// 初始 cap 为 10，len 为 10
slice = make([]int, 10)

// 初始 map，没有 size 参数
dict = make(map[int]int)

// 初始 channel
ch1 = make(chan int) // 无缓冲
ch1 = make(chan int,10) // 有缓冲
```

**slice 操作**

可以通过 `[lower-bound:upper-bound]` 来截取切片，其中 `upper-bound` 可以超出 `len` 但不能超过 `cap`。如下操作：

```go
slice := make([]int,0,10)
sliceRef := slice[1:cap(slice)]

fmt.Println(slice) // len:0 cap:10
fmt.Println(sliceRef) // len:9 cap:9
```

`append` 必须要使用返回值，可能会触发切片扩容，导致切片底层的内存变化，使用之前的 slice header 会导致内存访问错误。
```go
slice = append(slice,1)
```

slice 之间赋值都只是复制了一个对底层内存空间的引用，还是共享底层内存的，可以通过 `copy` 来拷贝一个切片到另一个切片，目标切片需要有足够的空间，否则只会最多复制到 `len(dst)`。

```go
slice := []int{1,2,3}
sliceCopy := make([]int,6)
copy(sliceCopy,slice)
fmt.Println(sliceCopy)
```

**type assert**

```go
// 类型断言
slice, ok := x.([]int)
```

**type switch**
```go
// 类型判断
switch v := interface{}(slice).(type) {
case []int:
	fmt.Println("slice")
}
```

**generic**
```go
// 泛型
func generic[T any](slice []T) []T {
	return slice
}
```

## 踩坑

**Q: 如下代码会输出什么？**
```go
func rangeTest() []*int {
	slice := []int{
		1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	}

	temp := []*int{}
	for _, v := range slice {
		temp = append(temp, &v)	
	}
	return temp
}

func main() {
	slice := rangeTest()
	for _, v := range slice {
		fmt.Println(*v)
	}
}
```
A: 在 Go 1.22 之前，会全部输出 10；在 Go 1.22 之后，会输出 1 到 10。1.22 版本 Fix 了这个问题，详见 [loopvar](https://go.dev/blog/loopvar-preview)。

**Q: sync.Pool 的使用**



## 其他

### 使用 embed 将文件嵌入 Binary 中

在Go中，从 1.16 版本开始，提供了一个新的特性来内嵌文件：`//go:embed` 指令。这使得你可以将文件和文件夹直接内嵌到你的 Go 二进制程序中。使用这个指令，你可以读取内嵌的文件，就像操作普通文件系统中的文件一样，但它们实际上是被编译进你的程序中的。
如果你想要内嵌一个目录中的所有 .yaml 文件，你可以采取如下步骤：

- 导入 `embed` 包
```go
import (
    "embed"
    // ... 其他导入
)
```
- 使用 `//go:embed` 指令：该指令会内嵌与 Go 源文件同一目录中的所有 .yaml 文件。这个 `yamlFiles` 变量得到的是一个 `embed.FS` 类型的文件系统对象，你可以像使用其他任何文件系统一样来使用它。
```go
//go:embed *.yaml
var yamlFiles embed.FS
```
- 访问内嵌文件：通过标准库中的io/fs包中的函数来访问这些文件。
```go
import (
    "embed"
    "io/fs"
    "log"
)

//go:embed *.yaml
var yamlFiles embed.FS

func main() {
    // 获取文件列表
    fileEntries, err := fs.ReadDir(yamlFiles, ".")
    if err != nil {
        log.Fatal(err)
    }

    for _, fileEntry := range fileEntries {
        bytes, err := fs.ReadFile(yamlFiles, fileEntry.Name())
        if err != nil {
            log.Fatal(err)
        }

        // 这里可以处理每个文件的bytes内容
        // 例如打印出来
        log.Printf("Contents of %s:\n%s\n", fileEntry.Name(), string(bytes))
    }
}
```

请注意，使用//go:embed时必须遵循的两个限制：

- `//go:embed` 只能应用于包级别的变量。
- 被内嵌的变量必须有 `embed.FS` 类型或者是字符串类型（`string`）、字节切片类型（`[]byte`）。

使用 `//go:embed` 对资源文件进行内嵌可以简化程序部署，因为你不需要单独地管理这些静态资源文件。它们都是程序的一部分被编译成单个二进制文件。

### 编译时动态地设置Go程序中的字符串变量

在 Go 语言中，go build 命令用于编译 Go 源码生成可执行文件。`-ldflags` 参数是一个编译时标志，它向 Go 的链接器（即 ld ）传递指令。`-X` 是 ldflags 中的一个选项，它可以设定包内的全局变量的值。

当你使用 `-ldflags "-X importpath.name=value"` 的格式时，你可以在编译时动态地设置 Go 程序中的字符串变量。这在设置版本号、构建时间、提交哈希等编译时变量时特别有用。
```go
go build -ldflags "-X mymod/cmd.Version=x.y.z"
```

- mymod/cmd 表示变量 `Version` 所在的包路径。
- `Version` 是你想要设置的变量名。
- x.y.z 是你为变量 `Version` 指定的值。

执行此命令后，包 mymod/cmd 中的 `Version` 变量在编译时将被设置为 x.y.z。通常，这个命令是在构建软件发行版本时使用，以便将版本信息嵌入生成的二进制文件中。

确保在使用 -X 参数时，变量的完整导入路径和名称是正确的，并且该变量在源代码中已定义为一个可导出（首字母大写）的全局变量。