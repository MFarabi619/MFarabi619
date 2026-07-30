// Copyright 2026 Mumtahin Farabi
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
// THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.


#ifndef RGPIO__LINUX__GPIO_H_
#define RGPIO__LINUX__GPIO_H_

/* lg's headers transitively #include <linux/gpio.h>, but the remote-client
 * sources we compile (rgpio, lgCfg, lgErr, lgDbg, lgMD5) reference no symbols
 * from it. This empty stub lets librgpio build on non-Linux hosts (e.g. macOS);
 * the real header is only needed by lg's local GPIO backend, which we don't build. */

#endif  // RGPIO__LINUX__GPIO_H_
