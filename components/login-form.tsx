'use client'

import { useFormStatus } from 'react-dom'
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { login } from "@/app/login/actions"

function SubmitButton() {
  const { pending } = useFormStatus()
  
  return (
    <Button
      type="submit"
      className="h-11 w-full bg-slate-900 text-white hover:bg-slate-800 transition-colors"
      disabled={pending}
    >
      {pending ? "Signing in..." : "Sign In"}
    </Button>
  )
}

export function LoginForm() {
  async function handleAction(formData: FormData) {
    await login(formData)
  }

  return (
    <div className="w-full max-w-md space-y-8 px-6 py-12">
      {/* Logo */}
      <div className="flex items-center gap-2">
        <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-slate-900">
          <svg className="h-6 w-6 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"
            />
          </svg>
        </div>
        <span className="text-2xl font-semibold text-slate-900">MedDoc AI</span>
      </div>

      {/* Heading */}
      <div className="space-y-2">
        <h1 className="text-3xl font-semibold tracking-tight text-slate-900">Welcome back</h1>
        <p className="text-sm text-slate-600">Sign in to your account to continue</p>
      </div>

      {/* Form */}
      <form action={handleAction} className="space-y-6">
        <div className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="email" className="text-sm font-medium text-slate-900">
              Email
            </Label>
            <Input
              id="email"
              name="email"
              type="email"
              placeholder="your.email@company.com"
              required
              className="h-11"
            />
          </div>

          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <Label htmlFor="password" className="text-sm font-medium text-slate-900">
                Password
              </Label>
              <a href="#" className="text-sm font-medium text-slate-600 hover:text-slate-900 transition-colors">
                Forgot password?
              </a>
            </div>
            <Input
              id="password"
              name="password"
              type="password"
              placeholder="Enter your password"
              required
              className="h-11"
            />
          </div>
        </div>

        <div className="space-y-3">
          <SubmitButton />

          <Button
            type="button"
            variant="outline"
            className="h-11 w-full border-slate-300 text-slate-700 hover:bg-slate-50 transition-colors bg-transparent"
          >
            <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor">
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M15 7a2 2 0 012 2m4 0a6 6 0 01-7.743 5.743L11 17H9v2H7v2H4a1 1 0 01-1-1v-2.586a1 1 0 01.293-.707l5.964-5.964A6 6 0 1121 9z"
              />
            </svg>
            SSO Login
          </Button>
        </div>
      </form>

      {/* Footer */}
      <div className="border-t border-slate-200 pt-6">
        <div className="flex items-center gap-2 text-xs text-slate-600">
          <svg className="h-4 w-4 text-slate-500" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              strokeWidth={2}
              d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"
            />
          </svg>
          <span>Protected by Enterprise Security Standards</span>
        </div>
      </div>
    </div>
  )
}
