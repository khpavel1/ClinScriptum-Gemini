"use client"

import { useRouter, usePathname, useSearchParams } from "next/navigation"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"

export function ProjectFilter() {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()
  
  const currentStatus = searchParams.get("status") || "all"

  const handleStatusChange = (value: string) => {
    const params = new URLSearchParams(searchParams.toString())
    
    if (value === "all") {
      params.delete("status")
    } else {
      params.set("status", value)
    }
    
    const newUrl = params.toString() ? `${pathname}?${params.toString()}` : pathname
    router.push(newUrl, { scroll: false })
  }

  return (
    <Select value={currentStatus} onValueChange={handleStatusChange}>
      <SelectTrigger className="w-[180px]">
        <SelectValue placeholder="Фильтр по статусу" />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">All</SelectItem>
        <SelectItem value="draft">Draft</SelectItem>
        <SelectItem value="active">Active</SelectItem>
        <SelectItem value="archived">Archived</SelectItem>
      </SelectContent>
    </Select>
  )
}

