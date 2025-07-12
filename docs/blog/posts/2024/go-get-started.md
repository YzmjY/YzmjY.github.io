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
```

**slice 操作**


**type assert**
```go
// 类型断言
slice, ok := interface{}(slice).([]int)
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



## 特性

