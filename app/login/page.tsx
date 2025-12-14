"use client"

import type React from "react"

import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import Link from "next/link"
import { useState } from "react"
import { useFormStatus } from "react-dom"
import { login } from "@/app/login/actions"

function SubmitButton() {
  const { pending } = useFormStatus()
  
  return (
    <Button
      type="submit"
      className="w-full bg-blue-600 hover:bg-blue-700 text-white"
      disabled={pending}
    >
      {pending ? "Signing in..." : "Sign In"}
    </Button>
  )
}

export default function LoginPage() {
  const [open, setOpen] = useState(false)
  const [resetEmail, setResetEmail] = useState("")
  const [submitted, setSubmitted] = useState(false)

  async function handleAction(formData: FormData) {
    await login(formData)
  }

  const handlePasswordReset = (e: React.FormEvent) => {
    e.preventDefault()
    setSubmitted(true)
    setTimeout(() => {
      setOpen(false)
      setSubmitted(false)
      setResetEmail("")
    }, 2000)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-slate-50 relative overflow-hidden">
      {/* Subtle technical background grid */}
      <div
        className="absolute inset-0 opacity-[0.03]"
        style={{
          backgroundImage: `
            linear-gradient(to right, rgb(100 116 139) 1px, transparent 1px),
            linear-gradient(to bottom, rgb(100 116 139) 1px, transparent 1px)
          `,
          backgroundSize: "40px 40px",
        }}
      />

      {/* Login Card */}
      <Card className="w-full max-w-md border-slate-200 shadow-sm relative z-10 mx-4">
        <CardHeader className="space-y-2 pb-4">
          <div className="flex items-center gap-2 mb-1">
            <div className="w-8 h-8 rounded bg-blue-600 flex items-center justify-center">
              <span className="text-white font-bold text-sm">CS</span>
            </div>
            <span className="font-semibold text-slate-900">ClinScriptum</span>
          </div>
          <CardTitle className="text-2xl font-semibold text-slate-900">Sign in to your account</CardTitle>
          <CardDescription className="text-slate-600">Enter your credentials to access the workspace</CardDescription>
        </CardHeader>

        <CardContent className="space-y-4 pb-4">
          <form action={handleAction} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="email" className="text-slate-700 font-medium">
                Email
              </Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="name@company.com"
                className="border-slate-200 focus-visible:ring-blue-600"
                required
              />
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="password" className="text-slate-700 font-medium">
                  Password
                </Label>
                <Dialog open={open} onOpenChange={setOpen}>
                  <DialogTrigger asChild>
                    <button 
                      type="button"
                      className="text-sm text-blue-600 hover:text-blue-700 hover:underline"
                    >
                      Forgot password?
                    </button>
                  </DialogTrigger>
                  <DialogContent className="sm:max-w-md border-slate-200">
                    <DialogHeader>
                      <DialogTitle className="text-slate-900">Reset password</DialogTitle>
                      <DialogDescription className="text-slate-600">
                        Enter your email address and we'll send you a link to reset your password.
                      </DialogDescription>
                    </DialogHeader>
                    {!submitted ? (
                      <form onSubmit={handlePasswordReset}>
                        <div className="space-y-4 py-4">
                          <div className="space-y-2">
                            <Label htmlFor="reset-email" className="text-slate-700 font-medium">
                              Email
                            </Label>
                            <Input
                              id="reset-email"
                              type="email"
                              placeholder="name@company.com"
                              value={resetEmail}
                              onChange={(e) => setResetEmail(e.target.value)}
                              className="border-slate-200 focus-visible:ring-blue-600"
                              required
                            />
                          </div>
                        </div>
                        <DialogFooter>
                          <Button type="submit" className="w-full bg-blue-600 hover:bg-blue-700 text-white">
                            Send reset link
                          </Button>
                        </DialogFooter>
                      </form>
                    ) : (
                      <div className="py-4">
                        <p className="text-sm text-slate-700 text-center">Reset link sent! Check your email.</p>
                      </div>
                    )}
                  </DialogContent>
                </Dialog>
              </div>
              <Input 
                id="password" 
                name="password"
                type="password" 
                className="border-slate-200 focus-visible:ring-blue-600"
                required
              />
            </div>

            <SubmitButton />
          </form>
        </CardContent>

        <CardFooter className="flex flex-col space-y-3 pt-2 pb-6">
          <p className="text-sm text-slate-600 text-center">
            Don't have an account?{" "}
            <Link href="/contact" className="text-blue-600 hover:text-blue-700 hover:underline font-medium">
              Contact Admin
            </Link>
          </p>
          <p className="text-xs text-slate-500 text-center">
            © {new Date().getFullYear()} ClinScriptum. All rights reserved.
          </p>
        </CardFooter>
      </Card>
    </div>
  )
}