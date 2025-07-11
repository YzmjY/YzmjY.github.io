---
date: 2025-07-11
categories:
  - Go
draft: false
---

# Go 笔记

![](../assert/go.png)
/// caption
///

<!-- more -->

## 基本语法


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



## 特性

