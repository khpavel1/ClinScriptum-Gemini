"use client"

import { useState } from "react"
import { useForm } from "react-hook-form"
import { zodResolver } from "@hookform/resolvers/zod"
import * as z from "zod"
import { toast } from "sonner"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Label } from "@/components/ui/label"
import { createProject } from "@/app/dashboard/actions"

// Zod schema for form validation
const createProjectSchema = z.object({
  studyCode: z.string().min(1, "Study code is required").max(20, "Study code must be 20 characters or less"),
  title: z.string().min(1, "Title is required"),
  sponsor: z.string().min(1, "Sponsor is required"),
  therapeuticArea: z.string().min(1, "Therapeutic area is required"),
})

type CreateProjectFormData = z.infer<typeof createProjectSchema>

const therapeuticAreas = [
  "Oncology",
  "Cardiology",
  "Neurology",
  "Immunology",
  "Infectious Diseases",
  "Endocrinology",
  "Other",
]

export function CreateProjectModal() {
  const [open, setOpen] = useState(false)

  const {
    register,
    handleSubmit,
    setValue,
    watch,
    reset,
    formState: { errors, isSubmitting },
  } = useForm<CreateProjectFormData>({
    resolver: zodResolver(createProjectSchema),
    defaultValues: {
      studyCode: "",
      title: "",
      sponsor: "",
      therapeuticArea: "",
    },
  })

  const therapeuticArea = watch("therapeuticArea")

  const onSubmit = async (data: CreateProjectFormData) => {
    try {
      // Создаем FormData для Server Action
      const formData = new FormData()
      formData.append("studyCode", data.studyCode)
      formData.append("title", data.title)
      formData.append("sponsor", data.sponsor)
      formData.append("therapeuticArea", data.therapeuticArea)

      // Вызываем Server Action
      const result = await createProject(formData)

      if (result.error) {
        toast.error("Ошибка", {
          description: result.error,
        })
        return
      }

      if (result.success) {
        toast.success("Проект создан", {
          description: "Проект успешно создан и добавлен в ваш список.",
        })
        setOpen(false)
        reset()
      }
    } catch (error) {
      console.error("Error creating project:", error)
      toast.error("Ошибка", {
        description: "Произошла непредвиденная ошибка при создании проекта.",
      })
    }
  }

  const handleCancel = () => {
    setOpen(false)
    reset()
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger asChild>
        <Button>Create Project</Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Create Project</DialogTitle>
          <DialogDescription>Enter the details for your new clinical study project.</DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
          <div className="space-y-4">
            {/* Study Code */}
            <div className="space-y-2">
              <Label htmlFor="studyCode">
                Study Code <span className="text-destructive">*</span>
              </Label>
              <Input
                id="studyCode"
                placeholder="e.g., CLIN-001"
                maxLength={20}
                aria-invalid={!!errors.studyCode}
                {...register("studyCode")}
              />
              {errors.studyCode && <p className="text-destructive text-xs">{errors.studyCode.message}</p>}
            </div>

            {/* Title */}
            <div className="space-y-2">
              <Label htmlFor="title">
                Title <span className="text-destructive">*</span>
              </Label>
              <Textarea
                id="title"
                placeholder="e.g., Phase III Study of Drug X in Patients with Condition Y"
                rows={3}
                aria-invalid={!!errors.title}
                {...register("title")}
              />
              {errors.title && <p className="text-destructive text-xs">{errors.title.message}</p>}
            </div>

            {/* Sponsor */}
            <div className="space-y-2">
              <Label htmlFor="sponsor">
                Sponsor <span className="text-destructive">*</span>
              </Label>
              <Input
                id="sponsor"
                placeholder="e.g., Pfizer"
                aria-invalid={!!errors.sponsor}
                {...register("sponsor")}
              />
              {errors.sponsor && <p className="text-destructive text-xs">{errors.sponsor.message}</p>}
            </div>

            {/* Therapeutic Area */}
            <div className="space-y-2">
              <Label htmlFor="therapeuticArea">
                Therapeutic Area <span className="text-destructive">*</span>
              </Label>
              <Select value={therapeuticArea} onValueChange={(value) => setValue("therapeuticArea", value)}>
                <SelectTrigger id="therapeuticArea" className="w-full" aria-invalid={!!errors.therapeuticArea}>
                  <SelectValue placeholder="Select therapeutic area" />
                </SelectTrigger>
                <SelectContent>
                  {therapeuticAreas.map((area) => (
                    <SelectItem key={area} value={area}>
                      {area}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {errors.therapeuticArea && <p className="text-destructive text-xs">{errors.therapeuticArea.message}</p>}
            </div>
          </div>

          <DialogFooter>
            <Button type="button" variant="ghost" onClick={handleCancel} disabled={isSubmitting}>
              Cancel
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isSubmitting ? "Creating..." : "Create Project"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
