---
title: java语言学习
date: 2025-08-15 21:13:47
tags: 
    - java
categories:
    - 基础知识
---

由浅入深介绍java语言中常用的基础语法，打好地基，写出优雅的代码。
<!-- more -->
# Java基本语法

# Java等待全部子线程执行完毕
使用CountDownLatch实现。
```java
import java.util.concurrent.CountDownLatch;

public class LatchExample {
    public static void main(String[] args) throws InterruptedException {
        int threadCount = 3;
        CountDownLatch latch = new CountDownLatch(threadCount);

        for (int i = 0; i < threadCount; i++) {
            new Thread(() -> {
                System.out.println(Thread.currentThread().getName() + " 执行中...");
                try {
                    Thread.sleep(1000); // 模拟任务
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }
                latch.countDown(); // 通知完成
            }, "子线程-" + i).start();
        }

        latch.await(); // 等待所有子线程完成
        System.out.println("所有子线程执行完毕，主线程继续");
    }
}
```
