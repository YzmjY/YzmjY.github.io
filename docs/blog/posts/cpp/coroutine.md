---
date: 2024-11-24
categories:
  - CPP
---

# Coroutines

> [Daily Bite of C++ Coroutines: Step by Step](https://simontoth.substack.com/p/daily-bite-of-c-coroutines-step-by)

C++20 标准库中新增了对协程的支持。对于大多数 C++用户来说，使用协程只需要遵循库的文档，提供协程类型即可。但是，如果你需要实现自定义协程类型，本篇文章就是为你准备的。
在本篇文章中，我们将介绍七种不同的协程类型，以此来介绍与协程有关的概念。

<!-- more -->

## 使用协程

在 C++中，满足以下两个条件的任何函数（除了`main`）都被视为一个协程：

- 函数体包含至少一个协程关键字：`co_return`, `co_yield`, `co_await`
- 返回类型符合协程要求（直接或通过 `std::coroutine_traits`）

对于被视为协程的函数，编译器会生成额外的代码来实现协程规定的行为。

C++标准库提供了`std::generator`（C++23），它可以用来实现惰性计算元素序列。`std::generator`可以通过`co_yield`关键字来生成元素，有以下两种方式：

- `co_yield value` : 生成单个元素
- `co_yield std::ranges::elements_of(range)` : 生成一个满足`range`的接口的元素序列

下例子展示了如何使用 `std::generator` 来实现斐波那契数列的计算。

```cpp
#include <generator>
#include <print>
#include <utility>

// The return type has to conform to coroutine requirements
std::generator<int> fibonacci(int cnt) {
    int a = 0;
    int b = 1;
    for (;cnt > 0; --cnt)
        // and the function must use at least one coroutine keyword
        co_yield std::exchange(a, std::exchange(b, a+b));
    // This coroutine naturally ends after the loop is exhausted
    // but we can also co_return to exit immediately.
}

int main() {
    for (int v : fibonacci(10)) {
        std::println("{}", v);
    }
}
```

`std::generator` 类型实现了`range`的接口，这意味着从调用者的角度来看，只是调用了一个返回值会`std::generator<T>`的函数，该返回值是一个可迭代的`range`类型。使用`std::generator`改写那些依赖于回调函数或者需要提前计算输出的程序非常有用。例如，使用`std::generator`实现不同的树遍历算法就非常简单。

```cpp
#include <print>
#include <generator>

struct Node {
    int value;
    Node* left;
    Node* right;
};

std::generator<Node*> pre_order(Node* root) {
    if (root == nullptr) co_return;

    co_yield root;
    co_yield std::ranges::elements_of(pre_order(root->left));
    co_yield std::ranges::elements_of(pre_order(root->right));
}

std::generator<Node*> in_order(Node* root) {
    if (root == nullptr) co_return;

    co_yield std::ranges::elements_of(in_order(root->left));
    co_yield root;
    co_yield std::ranges::elements_of(in_order(root->right));
}

std::generator<Node*> post_order(Node* root) {
    if (root == nullptr) co_return;

    co_yield std::ranges::elements_of(post_order(root->left));
    co_yield std::ranges::elements_of(post_order(root->right));
    co_yield root;
}


#include <vector>
#include <memory>

std::vector<std::unique_ptr<Node>> make_tree();

int main() {
    auto tree = make_tree();
    Node* root = tree[0].get();

    for (Node* node : pre_order(root))
        std::print("{} ", node->value);
    std::println("");

    for (Node* node : in_order(root))
        std::print("{} ", node->value);
    std::println("");

    for (Node* node : post_order(root))
        std::print("{} ", node->value);
    std::println("");
}

std::vector<std::unique_ptr<Node>> make_tree() {
    std::vector<std::unique_ptr<Node>> tree;

    tree.push_back(std::make_unique<Node>(4));
    Node* root = tree.back().get();

    tree.push_back(std::make_unique<Node>(2));
    Node* left = tree.back().get();
    root->left = left;

    tree.push_back(std::make_unique<Node>(6));
    Node* right = tree.back().get();
    root->right = right;

    tree.push_back(std::make_unique<Node>(1));
    left->left = tree.back().get();
    tree.push_back(std::make_unique<Node>(3));
    left->right = tree.back().get();

    tree.push_back(std::make_unique<Node>(5));
    right->left = tree.back().get();
    tree.push_back(std::make_unique<Node>(7));
    right->right = tree.back().get();

    return tree;
}
```

通过其他库提供的协程类型也许会提供不同的接口和行为。因此，在使用自定义协程类型之前，请始终检查相应的文档。

## 创建协程

在使用 C++的 coroutine 之前，要明确一件事情：C++的 coroutine 并没有定义一个异步模型。相反，coroutine 类型可以适配几乎任何工作流。
创建一个协程需要明确三个主要部分：返回类型（例如 `std::generator`），`promise` 类型（描述协程行为）和 `awaitable` 类型（控制低层机制如何暂停和恢复协程）。

在下面的章节中，我们将介绍七种不同的协程类型，每个类型都介绍了更多的概念。

### 创建一个例程

coroutine 是一般函数的泛化。因此，让我们从实现一个返回 void 的函数类型开始来逐步实现一个完整的 coroutine 类型。下面通过使用 C++提供的 coroutine 的基础设施，实现一个简单的 `Routine` 类型(即只是根据输入执行一段计算任务，无返回值)，我们可以快速地了解 coroutine 中 `promise_type` 中所有可用的自定义点。

```cpp
#include <coroutine>
#include <print>

struct RoutinePromise;

struct Routine {
    // The return type has to contain a promise_type
    using promise_type = RoutinePromise;
};

struct RoutinePromise {
    // This function is used to create the instance
    // of the return type for the caller
    Routine get_return_object() { return {}; }

    // What should happen before the coroutine body starts
    std::suspend_never initial_suspend() noexcept { return {}; }
    // What should happen after the coroutine body has finished
    std::suspend_never final_suspend() noexcept { return {}; }
    // What should happen when the coroutine executes co_return;
    void return_void() {}
    // What should happen when there is an unhandled exception
    void unhandled_exception() {}
};

int main() {
    auto coro = [] -> Routine {
        std::println("Running...");
        co_return;
    };

    auto x = coro(); // coroutine starts and runs to completion
    // decltype(x) == Routine
    static_assert(std::is_same_v<decltype(x), Routine>);

    coro(); // Because the return type is empty, this is the same as above
}
```

`promise_type`可以定义为一个嵌套类型，而不必像上面的例子中通过一个 `using` 别名来定义。首先介绍`promise_type`中的两个自定义点：`initial_suspend`和`final_suspend`。这两个函数返回一个 `awaitable` 类型（我们将在下一节讨论）。`initial_suspend`在协程体开始之前被调用，`final_suspend`在协程体结束之后被调用。
通过 `awaitable` 类型，我们可以来控制下面三个行为：

- 继续运行
- 返回控制给调用者(或最后一个 resumer)
- 转移控制给另一个协程

C++标准提供了两种 `awaitable` 类型：`std::suspend_never`（协程继续运行）和 `std::suspend_always`（控制返回给调用者）。在一般的`Routine`中，我们希望程序一直运行到完成，因此，我们使用 `std::suspend_never` 作为 `initial_suspend` 和 `final_suspend` 的返回类型。

```cpp
auto coro = [] -> Routine {
    std::println("Running...");
    co_return;
};

auto x = coro(); // coroutine starts and runs to completion

coro(); // Because the return type is empty, this is the same as above
```

上述实现的一个问题在于，函数的返回类型是固定的(对应上述例子中的`Routine`)。由于 `Routine` 是我们自己实现的类型，我们可以为它指定一个`promise_type`，但当我们希望能够编写一个返回类型来自一个你无法修改的第三方库的协程，上面的实现是不合适的。对于这种情况，标准库提供了`std::coroutine_traits`自定义点。

```cpp
#include <coroutine>
#include <print>

// No need to modify
struct Routine {};

// Any coroutine returning Routine
template <typename... Arg>
struct std::coroutine_traits<Routine, Arg...> {
    using promise_type = RoutinePromise;
};

int main() {
    auto coro = [] -> Routine {
        std::println("coro running...");
        co_return;
    };

    auto x = coro(); // coroutine starts and runs to completion
    // decltype(x) == Routine
    static_assert(std::is_same_v<decltype(x), Routine>);

    coro(); // Because the return type is empty, this is the same as above
}
```

如上所示，假如`Routine`类型来自一个第三方库，我们可以在`std::coroutine_traits`中添加一个特化，以便于编译器能够找到正确的 `promise_type`。

### 创建一个函数

对于一个`Routine`，我们可以忽略它的返回类型，但当我们使用协程的基础设施实现一个带返回值的`Function`时，则需要一个机制来让协程和调用者（只有通过返回类型值这一个手段）进行通信。
C++标准库提供了`std::coroutine_handle`类型来控制对应的协程和访问它的`promise`类型。为了使下面的示例简洁，我们将包装`std::coroutine_handle`（具有引用语义）到一个 RAII 对象中。

```cpp
template <typename promise_type>
struct owning_handle {
    owning_handle() : handle_() {}
    owning_handle(std::nullptr_t) : handle_(nullptr) {}
    owning_handle(std::coroutine_handle<promise_type> handle) : handle_(std::move(handle)) {}

    owning_handle(const owning_handle<promise_type>&) = delete;
    owning_handle(owning_handle<promise_type>&& other) : handle_(std::exchange(other.handle_, nullptr)) {}
    owning_handle<promise_type>& operator=(const owning_handle<promise_type>&) = delete;
    owning_handle<promise_type>& operator=(owning_handle<promise_type>&& other) {
        handle_ = std::exchange(other.handle_, nullptr);
        return *this;
    }
    promise_type& promise() { return handle_.promise(); }
    ~owning_handle() {
        if (handle_)
            handle_.destroy();
    }
private:
    std::coroutine_handle<promise_type> handle_;
}
```

注意我们在析构函数中显式销毁了协程。
向调用者传递返回值的一个简单的解决方法是将结果存储在 promise 中。如果我们给调用者访问协程句柄的权限，调用者可以通过句柄读取存储的值。
但是，当 coroutine 运行结束，promise 被销毁，因此我们需要保持协程的存活。

```cpp
#include <coroutine>
#include <print>
#include <utility>

template <typename T>
struct Function;

template <typename T>
struct FunctionPromise {
    using handle_t = std::coroutine_handle<FunctionPromise<T>>;
    // To read the result from the coroutine,
    // the caller needs to have access to it
    Function<T> get_return_object() {
        // Construct a coroutine handle from this promise
        return Function<T>{handle_t::from_promise(*this)};
    }

    std::suspend_never initial_suspend() noexcept { return {}; }
    // Because we need to give the caller a chance to read
    // the result, the coroutine now cannot finish after
    // completing the body. It needs to stick around.
    std::suspend_always final_suspend() noexcept { return {}; }

    // The mechanism used to "return" a result.
    // We can simply store it.
    template <std::convertible_to<T> Arg>
    void return_value(Arg&& result) {
        result_ = std::forward<Arg>(result);
    }

    void unhandled_exception() {}

    // The result of the coroutine stored in the promise
    T result_;
};

```

在`get_return_object`中，我们将对协程句柄的访问权限传递给返回对象,从而使调用者可以访问协程的结果。在`final_suspend`中，我们返回`std::suspend_always`，这将返回控制给调用者（从而保留协程存活），调用者则可以通过协程句柄访问协程内部的对象。`return_value`方法为协程提供了一个通过`return`返回结果的机制。在本例中，我们允许任何可以转换为 `T` 的参数；然而，这完全取决于实现者。你也可以通过提供多个 `return_value` 的实现来依赖重载解析。
在我们的示例中，我们需要实现对应的构造函数和一个 `helper` 方法来访问协程的结果。

```cpp
template <typename T>
struct Function {
    using promise_type = FunctionPromise<T>;

    // Store the coroutine handle
    explicit Function(promise_type::handle_t handle)
      : handle_(handle) {}

    // Interface for extracting the result
    T get() { return handle_.promise().result_; }
    operator T() { return get(); }
private:
    owning_handle<promise_type> handle_;
};
```

协程返回后依然存活(`final_suspend`),因此清理资源的责任属于返回类型，上面的例子通过一个 RAII 类型`owning_handle`解决了这个问题。

```cpp
int main() {
    auto coro = [] -> Function<int> {
        std::println("Running...");
        co_return 42;
    };

    auto x = coro();
    int result = x.get(); // Get the result
    std::println("result == {}", result);

    int y = coro(); // Same, but through implicit conversion
    std::println("y == {}", y);
}
```

## 处理异常

在实现一个函数协程之后，我们需要考虑异常处理。当异常没有在协程中被捕获时，编译器生成的代码将调用 unhandled_exception 方法。
我们有两种选择：调用 std::terminate 或存储当前正在飞行的异常并在调用者尝试访问结果时重新抛出它。

```cpp
int main() {
    auto coro = [] -> Function<int> {
        throw std::runtime_error("Error");
        co_return 42;
    };

    auto x = coro();
    int result = x.get(); // Get the result
    std::println("result == {}", result);

    int y = coro(); // Same, but through implicit conversion
    std::println("y == {}", y);
}
```

我们可以使用`std::current_exception`, `std::exception_ptr`和`std::rethrow_exception`来捕获和重新抛出异常。

```cpp
struct FunctionPromise {
    /* ... */
    void unhandled_exception() {
        exception_ = std::current_exception();
    }
    std::exception_ptr exception_;
}

template <typename T>
struct Function {
    /*... */
    operator T() {
        if (handle_.promise().exception_) {
            std::rethrow_exception(handle_.promise().exception_);
        }
        return handle_.promise().result_;
    }
};

auto coro = []->Function<int> {
    throw std::runtime_error("Error");
    co_return 42;
};

try {
    auto x = coro();
} catch (const std::exception& e) {
    std::println("Caught exception: {}", e.what());
}

```

为了简单起见，下面的示例将使用 std::terminate 变体。

## 创建一个惰性函数

前面两个例子（Routine 和 Function）很好的介绍了协程的基础知识。然而并没有揭示我们为什么需要协程，上面两个例子使用 C 都可以编写并达到目的。惰性计算函数是在没有协程的情况下无法简单实现的场景。与前面的例子不同的是，惰性计算函数在被请求结果之前不应该运行，这意味着我们需要改变 `initial_suspend` 的返回类型为 `std::suspend_always`，这将挂起协程并返回控制给调用者。

```cpp
template <typename T>
struct LazyFunction;

template <typename T>
struct LazyFunctionPromise {
    using handle_t = std::coroutine_handle<LazyFunctionPromise<T>>;
    // Get the caller access to the handle
    LazyFunction<T> get_return_object() {
        return LazyFunction<T>{handle_t::from_promise(*this)};
    }

    // Immediately return control to the caller
    std::suspend_always initial_suspend() noexcept { return {}; }
    // Keep the coroutine alive so we can read the result
    std::suspend_always final_suspend() noexcept { return {}; }

    // Support for co_return
    template <std::convertible_to<T> Arg>
    void return_value(Arg&& result) {
        result_ = std::forward<Arg>(result);
    }
    void unhandled_exception() {}
    T result_;
};
```

由于不再自动运行协程，我们将启动协程的责任交给返回值。当我们尝试访问返回值时，我们必须确保协程已经完成运行。

```cpp
template <typename T>
struct LazyFunction {
    using promise_type = LazyFunctionPromise<T>;

    // Store the coroutine handle
    explicit LazyFunction(promise_type::handle_t handle)
      : handle_(handle) {}

    T get() {
        // If the coroutine body has not finished running, resume it
        if (not handle_.done())
            handle_.resume();
        return handle_.promise().result_;
    }

    operator T() { return get(); }
private:
    owning_handle<promise_type> handle_;
};
```

请注意，`std::coroutine_handle` 提供了 `done` 和 `resume` 方法，我们通过我们的 RAII 包装器封装它们。

```cpp
int main() {
    auto coro = [] -> LazyFunction<int> {
        std::println("Running...");
        co_return 42;
    };

    {
    auto x = coro();
    int result = x.get(); // Run the coroutine and get the result
    int other = x.get(); // Get the result

    std::println("result == {}, other == {}", result, other);
    } // coroutine held by x destroyed

    {
    int y = coro(); // Same, but through implicit conversion,
                    // coroutine is run and destroyed as part
                    // of this expression.
    std::println("y == {}", y);
    }
}
```

## 创建 Generator

虽然标准库提供了 `std::generator`，编写我们自己的仍然是一个很好的练习，也是一个很好的方式引入`co_yield`。
在前面的例子中，我们只生成了一个结果。然而，我们可以使用 `co_yield` 来重复生成值，而 `co_return` 仅用于提前终止。
`co_yield`类似带参数的`co_return`。与前面的例子一样，我们允许任何可以转换为 T 的参数。

```cpp
template <typename T>
struct Generator;

template <typename T>
struct GeneratorPromise {
    using handle_t = std::coroutine_handle<GeneratorPromise<T>>;
    // Get the caller access to the handle
    Generator<T> get_return_object() {
        return Generator<T>{handle_t::from_promise(*this)};
    }

    // Immediately return control to the caller
    std::suspend_always initial_suspend() noexcept { return {}; }
    // Keep the coroutine alive so we can read the final result
    std::suspend_always final_suspend() noexcept { return {}; }

    // Support for co_yield
    template <std::convertible_to<T> Arg>
    std::suspend_always yield_value(Arg&& result) {
        result_ = std::forward<Arg>(result);
        return {};
    }
    // Support for co_return
    void return_void() {}
    void unhandled_exception() {}
    T result_;
};
```

`co_yield`与`co_return`一个重要的区别是 `co_yield`返回一个 `awaitable` 的值。这给我们提供了另一个定制点，控制在`co_yield`的返回结果之后的协程执行权，有三种主要选项：

- 协程继续运行
- 控制返回给调用者/恢复者
- 控制转移到另一个协程

在 `Generator` 中，我们希望将控制权返回给调用者，这意味着我们可以返回标准的 `std::suspend_always`。

```cpp
template <typename T>
struct Generator {
    using promise_type = GeneratorPromise<T>;

    // Store the coroutine handle
    explicit Generator(promise_type::handle_t handle)
      : handle_(handle) {}

    bool exhausted() {
        if (not handle_.done())
            handle_.resume();
        return handle_.done();
    }

    T get() {
        return handle_.promise().result_;
    }
private:
    owning_handle<promise_type> handle_;
};
```

同时，我们需要在返回类型中增加一个功能，来支持恢复 coroutine 的执行，以生成下一个值。

```cpp
int main() {
    auto coro = [] -> Generator<int> {
        co_yield 1;
        co_yield 2;
        co_yield 3;
        co_yield 4;
        co_yield 5;
        co_return;
    };

    auto empty = [] -> Generator<int> {
        co_return;
    };


    auto x = coro();
    while (not x.exhausted()) {
        int result = x.get();
        std::println("result == {}", result);
    }

    auto y = empty();
    while (not y.exhausted()) {
        int result = y.get();
        std::println("result == {}", result);
    }
}
```

虽然这个实现可以工作，但它的复杂性相当高。我们必须单独启动 coroutine，检查它是否耗尽（这将恢复 coroutine），然后仅然后读取当前值。std::generator 通过支持`range`接口来克服这个复杂性，我们可以仿照为自己的 Generator 也实现一个。
首先，我们需要一个迭代器类型。

```cpp
template <typename T>
struct Generator {
    /*... */

    struct iterator {
        using value_type = T;
        using difference_type = ptrdiff_t;

        // Move-only interface
        iterator(owning_handle<promise_type> handle) : handle_(std::move(handle)) {}
        iterator(iterator&& other) noexcept : handle_{std::exchange(other.handle_, {})} {};
        iterator& operator=(iterator&& other) noexcept {
            handle_ = std::exchange(other.handle_, {});
            return *this;
        }

        // Read current value
        T& operator*() const {
            return handle_.promise().result_;
        }
        // Advance the iterator
        iterator& operator++() {
            assert(not handle_.done());
            handle_.resume();
            return *this;
        }
        void operator++(int) {
            return ++*this;
        }

        // We are done when the coroutine is done
        // done is called when we call iter == end()
        friend bool operator==(const iterator& i, std::default_sentinel_t) {
            return i.handle_.done();
        }
    private:
        owning_handle<promise_type> handle_;
    };

private:
    owning_handle<promise_type> handle_;
};
```

为避免空的 coroutine 导致的问题，我们在返回 `begin` 迭代器时必须恢复 coroutine。如果 coroutine 立即完成，`handle_.done()` 将返回 true，这意味着 `begin == default_sentinel_t{}`。

```cpp
template <typename T>
struct Generator {
    /*... */
    iterator begin() {
        handle_.resume();
        return iterator{std::move(handle_)};
    }

    std::default_sentinel_t end() const noexcept { return {}; }
};
```

有了上述的`range`接口，我们现在可以使用 range for 循环来迭代所有生成的值。

```cpp
int main() {
    auto coro = [] -> Generator<int> {
        co_yield 1;
        co_yield 2;
        co_yield 3;
        co_return;
    };

    auto empty = [] -> Generator<int> {
        co_return;
    };

    for (auto result : coro()) {
        std::println("result == {}", result);
    }

    for (auto result : empty()) {
        std::println("result == {}", result);
    }
}
```

## 多任务协作

目前为止，我们了解一种由调用方控制的`in-flight`协程。协程更加有趣的用例通常设计由调度程序/执行程序控制的多个同时执行的协程。
我们可以从一个简单的协作式多任务处理案例开始，其中多个协程共享同一个执行线程，并自愿放弃对该线程的控制权，让其他协程运行。
为了实现这一点，我们需要了解 `awaitable` 类型。我们已经了解到 `std::suspend_always`（将控制权返回给调用方）和 `std::suspend_never`（让协程继续）。我们还讨论了返回 `awaitable` 的三种方法：`initial_suspend`、`final_suspend` 和 `yield_value`。
在这背后有一个被隐藏起来的 `co_await` 关键字，主要是因为这个关键字出现在编译器生成的代码中。生成的对上述方法的调用具有以下形式：

```cpp
co_await promise().initial_suspend();
co_await promise().final_suspend();
co_await promise().yield_value(arg); // 等同于 co_yield arg;
```

这意味着我们在调用这些返回的 `awaitable` 类型的方法前使用 `co_await`关键字，然后，这反过来又控制接下来会发生什么：

- 协程继续运行
- 控制返回给调用者/恢复者
- 控制转移到另一个协程

我们也可以在协程主体中直接调用 `co_await`。例如，如果我们调用 `co_await std：：suspend_always{}`，我们将暂停协程并将控制权返回给调用者，调用者可以根据需要销毁或恢复协程。我们也可以通过本节介绍的调度器（Scheduler）来做这件事情。

```cpp
struct Scheduler {
    // Add a coroutine under the control of the scheduler
    // 将协程句柄保存在Scheduler的一个内部队列中
    void enqueue(std::coroutine_handle<> handle) const {
        coroutines_.push_back(handle);
    }

    void run() const {
        // As long as we have active coroutines, continue running
        // 还有有协程在运行
        while (not coroutines_.empty()) {
            // Grab the first coroutine from the queue
            // 拿到一个还未执行完成的协程
            auto active = coroutines_.front();
            coroutines_.pop_front();

            // 恢复执行
            active.resume();
            // The coroutine is owned by the scheduler,
            // meaning it is responsible for destroying it
            if (active.done())
                active.destroy();
        }
    }


    WakeupAwaitable wake_up() const { return WakeupAwaitable{}; }
private:
    // Monostate
    static std::list<std::coroutine_handle<>> coroutines_;
};
std::list<std::coroutine_handle<>> Scheduler::coroutines_{};
```

这也是我们第一次使用类型擦除的 `std：：coroutine_handle<>`。调度程序仅管理协程的生命周期，不需要访问任何协程内的细节。
对于协程类型，我们返回到一个简单的任务，其中包含一个重要的附加功能：将协程的所有权移交给调度程序的 detach 方法。

```cpp
struct Task {
    struct promise_type {
        using handle_t = std::coroutine_handle<promise_type>;
        // Get the caller access to the handle
        Task get_return_object() {
            return Task{handle_t::from_promise(*this)};
        }
        std::suspend_always initial_suspend() noexcept { return {}; }
        std::suspend_always final_suspend() noexcept { return {}; }
        void return_void() {}
        void unhandled_exception() {}
    };

    void detach() {
        // Give control of this coroutine to the scheduler
        Scheduler{}.enqueue(handle_.detach());
    }

    // Store the coroutine handle
    explicit Task(promise_type::handle_t handle)
      : handle_(handle) {}
private:
    owning_handle<promise_type> handle_;
};
```

最后一部分是 `awaitable` 类型，它用来实现暂停一个协程并让其他协程运行。

```cpp
struct WakeupAwaitable {
    // Opportunity for early continuation, returning true
    // will let the coroutine continue without suspending.
    // 最早执行，返回true则协程继续执行，不挂起
    bool await_ready() { return false; }
    // 协程被挂起后执行
    // Called after the coroutine is suspended, controls
    // what happens next. The void returning variant returns
    // control to the caller.
    void await_suspend(std::coroutine_handle<> ctx) {
        // Re-schedule the suspended coroutine
        // ctx is a handle to the suspended coroutine
        Scheduler{}.enqueue(ctx);
    }
    // Called as the last part of evaluating co_await,
    // the coroutine is resumed just before this call
    // (if it was suspended in the first place).
    // co_await表达式的最后一部分，协程被恢复后执行
    void await_resume() {}
};
```

当协程执行 `co_await WakeupAwaitable{}` 时，它将被暂停，控制权将返回给调用方，即调度程序。

## 使用 asynchrony

与 asynchrony 交互时，您通常需要使用协程以满足您的特定需求。但是，一种相当容易集成的异步类型是 time。它还引入了一个谈论`await_transform`的绝佳机会。
主要变化是我们的调度程序，它现在需要一个有序的容器来存储协程句柄，每个句柄也附加了唤醒时间。

```cpp
struct Scheduler {
    using time_point = std::chrono::time_point<std::chrono::system_clock>;

    // Add a coroutine under the control of the scheduler
    void enqueue(std::coroutine_handle<> handle, time_point time = std::chrono::system_clock::now()) const {
        pending_coroutines_.push(std::make_pair(time, handle));
    }

    void run() const {
        while (not pending_coroutines_.empty()) {
            if (pending_coroutines_.top().first >
                std::chrono::system_clock::now()) {
                std::this_thread::sleep_until(pending_coroutines_.top().first);
            }

            auto active = pending_coroutines_.top().second;
            pending_coroutines_.pop();

            active.resume();

            if (active.done())
                active.destroy();
        }
    }

    struct WakeupAwaitable {
        // Opportunity for early continuation, returning true
        // will let the coroutine continue without suspending.
        bool await_ready() { return false; }
        // Called after the coroutine is suspended, controls
        // what happens next. The void returning variant returns
        // control to the caller.
        void await_suspend(std::coroutine_handle<> ctx) {
            // The argument is a handle to the suspended coroutine.
            Scheduler{}.enqueue(ctx, time_);
        }
        // Called as the last part of evaluating co_await,
        // the coroutine is resumed just before this call
        // (if it was suspended in the first place).
        void await_resume() {}

        time_point time_;
    };

    WakeupAwaitable wake_up() const { return WakeupAwaitable{std::chrono::system_clock::now()}; }
    WakeupAwaitable wake_up(time_point time) const { return WakeupAwaitable{time}; }
private:
    // Monostate
    using timed_coroutine = std::pair<time_point, std::coroutine_handle<>>;
    static std::priority_queue<timed_coroutine, std::vector<timed_coroutine>, std::greater<>> pending_coroutines_;
};

std::priority_queue<Scheduler::timed_coroutine, std::vector<Scheduler::timed_coroutine>, std::greater<>> Scheduler::pending_coroutines_{};
```

扩展上一个示例中的 Scheduler 接口来实现这个需求，一个自然的做法是 `co_await Scheduler{}.wake_up（time_point）`;但是，这有点麻烦。如果我们能写 `co_await time_point` 会干净得多。我们可以在 `promise_type` 上使用 `await_transform` 方法来实现这一点。

```cpp
struct promise_type {
    using handle_t = std::coroutine_handle<promise_type>;
    // Get the caller access to the handle
    Task get_return_object() {
        return Task{handle_t::from_promise(*this)};
    }
    std::suspend_always initial_suspend() noexcept { return {}; }
    std::suspend_always final_suspend() noexcept { return {}; }
    void return_void() {}
    void unhandled_exception() {}
    auto await_transform(std::chrono::time_point<std::chrono::system_clock> time) const {
        return Scheduler{}.wake_up(time);
    }
};
```

但是，如果 `promise_type` 定义了至少一个 `await_transform`，则只有与其中一个 `await_transform` 重载匹配的类型才能与 `co_await` 一起使用

```cpp
int main() {
    using namespace std::chrono;
    auto coro = [] -> Task {
        auto time = system_clock::now();
        std::println("{}", system_clock::now());
        co_await (time+200ms);
        std::println("{}", system_clock::now());
        co_await (time+400ms);
        std::println("{}", system_clock::now());
    };

    coro().detach();
    coro().detach();

    Scheduler{}.run();
}
```

## 可等待的协程

我们将介绍的最后一种协程类型是 `awaitable coroutine`。在前面的示例中，我们让协程等待事件。
虽然基于事件的触发在异步系统中非常典型，但有时我们希望等待操作完成。将这些操作建模为协程也非常方便。
您可能考虑直接调用另一个协程;但是，这样存在以下两个问题：

- 操作完成后如何恢复父协程（考虑到操作可能需要暂停以等待事件或其他操作）？
- 在一个严重依赖 coroutines 的系统中，我们最终可能会有数百万个正在进行的 coroutine，这些 coroutine 可能会深度嵌套（比 functions 更激进）。我们如何避免堆栈空间不足？

这些问题可以通过添加一个依赖于对称传输的可等待类型添加间接层来解决。

```cpp
AwaitableTask child() {
    co_return;
}

AwaitableTask parent() {
    // Start child and wait until it is completed
    co_await child();
    co_return;
}
```

我们从基本的 Task 接口开始，我们使用 awaitable 类型接口对其进行扩展。

```cpp
struct AwaitableTask {
    struct promise_type {
        using handle_t = std::coroutine_handle<promise_type>;
        // Get the caller access to the handle
        AwaitableTask get_return_object() {
            return AwaitableTask{handle_t::from_promise(*this)};
        }

        std::suspend_always initial_suspend() noexcept { return {}; }
        ContinuationAwaitable final_suspend() noexcept {
            return { continuation_ };
        }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }

        std::coroutine_handle<> continuation_{std::noop_coroutine()};
    };

    // Store the coroutine handle
    explicit AwaitableTask(std::coroutine_handle<promise_type> handle)
      : handle_(handle) {}

    // Awaitable interface
    bool await_ready() noexcept { return false; }
    // When we await on the result of calling a coroutine
    // the coroutine will start, but will also remember its caller
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> caller) noexcept {
        // Remember the caller
        handle_.promise().continuation_ = caller;
        // Returning a coroutine handle will run the corresponding coroutine
        return handle_.raw_handle();
    }
    void await_resume() {}

    void run_until_completion() {
        while (not handle_.done())
            handle_.resume();
    }

private:
    owning_handle<promise_type> handle_;
};
```

当我们 `co_await coroutine()` 时，我们希望协程挂起，从而生成 `result` 类型的实例。然后，`co_await` 运算符将调用`awaitable`的接口，在本例中，该接口使用 `await_supend` 的协程句柄版本。
我们从 `await_ready` 返回 `false` 以暂停调用方，然后返回被调用方的句柄以开始执行。但是，我们还会记住调用方，以便在被调用方完成执行后恢复它。

```cpp
struct ContinuationAwaitable {
    bool await_ready() noexcept { return false; }
    std::coroutine_handle<> await_suspend(std::coroutine_handle<>) noexcept {
        return continuation_;
    }
    void await_resume() noexcept {}
    std::coroutine_handle<> continuation_{std::noop_coroutine()};
};
struct AwaitableTask {
    struct promise_type {
        using handle_t = std::coroutine_handle<promise_type>;
        // Get the caller access to the handle
        AwaitableTask get_return_object() {
            return AwaitableTask{handle_t::from_promise(*this)};
        }

        std::suspend_always initial_suspend() noexcept { return {}; }
        ContinuationAwaitable final_suspend() noexcept {
            return { continuation_ };
        }
        void return_void() {}
        void unhandled_exception() { std::terminate(); }

        std::coroutine_handle<> continuation_{std::noop_coroutine()};
    };

    // Store the coroutine handle
    explicit AwaitableTask(std::coroutine_handle<promise_type> handle)
      : handle_(handle) {}

    // Awaitable interface
    bool await_ready() noexcept { return false; }
    // When we await on the result of calling a coroutine
    // the coroutine will start, but will also remember its caller
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> caller) noexcept {
        // Remember the caller
        handle_.promise().continuation_ = caller;
        // Returning a coroutine handle will run the corresponding coroutine
        return handle_.raw_handle();
    }
    void await_resume() {}

    void run_until_completion() {
        while (not handle_.done())
            handle_.resume();
    }

private:
    owning_handle<promise_type> handle_;
};
```

虽然这一切都有效，但您可能想知道是否可以将相同的逻辑应用于函数，事实上，您可以。`co_await` 表达式的结果是 `await_resume` 的结果。

```cpp
template <typename T>
struct AwaitableFunction {
    struct promise_type {
        using handle_t = std::coroutine_handle<promise_type>;
        // Get the caller access to the handle
        AwaitableFunction get_return_object() {
            return AwaitableFunction{handle_t::from_promise(*this)};
        }

        std::suspend_always initial_suspend() noexcept { return {}; }
        ContinuationAwaitable final_suspend() noexcept {
            return { continuation_ };
        }
        // Same logic as in Function example
        template <std::convertible_to<T> Arg>
        void return_value(Arg&& result) {
            result_ = std::forward<Arg>(result);
        }
        void unhandled_exception() { std::terminate(); }

        std::coroutine_handle<> continuation_{std::noop_coroutine()};
        T result_;
    };

    // Store the coroutine handle
    explicit AwaitableFunction(std::coroutine_handle<promise_type> handle)
      : handle_(handle) {}

    // Awaitable interface
    bool await_ready() noexcept { return false; }
    // When we await on the result of calling a coroutine
    // the coroutine will start, but will also remember its caller
    std::coroutine_handle<> await_suspend(std::coroutine_handle<> caller) noexcept {
        // Remember the caller
        handle_.promise().continuation_ = caller;
        // Returning a coroutine handle will run the corresponding coroutine
        return handle_.raw_handle();
    }
    T await_resume() {
        return handle_.promise().result_;
    }

    void run_until_completion() {
        while (not handle_.done())
            handle_.resume();
    }

private:
    owning_handle<promise_type> handle_;
};
```

这允许我们从可等待的协程返回值，并将任务与函数混合和匹配。

```cpp
AwaitableFunction<int> child_func() {
    co_return 42;
}

AwaitableTask other_parent() {
    int v = co_await child_func();
    std::println("Child returned: {}", v);
    co_return;
}

```

## 结论

通过本篇文章，我们了解了其中不同形式的 coroutine:

- routine

- function

- lazy function

- generator

- cooperative tasks

- cooperative tasks with asynchrony

- awaitable coroutines
